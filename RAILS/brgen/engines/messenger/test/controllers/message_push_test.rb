# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A chat message is not a Notification row, so NativePushJob, which only ever
# fired from Notification, never sent one: a message reached web push and no
# phone. These pin the APNs half beside the web half, with the same filters.
class MessagePushTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @sender = create_user("push_sender")
    @reader = create_user("push_reader")
    @muted = create_user("push_muted")
    @vapid_before = Rails.application.config.x.vapid

    @group = Conversation.create_group!(creator: @sender, name: "Middag", users: [ @reader, @muted ])
    ConversationParticipant.find_by!(conversation: @group, user: @muted).update!(muted_at: Time.current)
    host! "brgen.no"
    post session_path, params: { email_address: @sender.email_address, password: "password123" }
  end

  teardown do
    Rails.application.config.x.vapid = @vapid_before
    ActsAsTenant.current_tenant = nil
  end

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def native_pushes_for(params)
    sent = []
    Apns.stub(:configured?, true) do
      NativePushJob.stub(:perform_later, ->(**payload) { sent << payload }) do
        post conversation_messages_path(@group), params: { message: params }
      end
    end
    sent
  end

  test "a message reaches the reader's phone, not a muted member's, in the conversation's own thread" do
    sent = native_pushes_for(content: "Taco kl 18?", message_type: "text")

    assert_equal [ @reader.id ], sent.map { |payload| payload[:user_id] }
    assert_equal "Taco kl 18?", sent.first[:body]
    assert_equal @sender.display_name, sent.first[:title]
    assert_equal "brgen-conversation-#{@group.id}", sent.first[:thread]
    assert_equal "/conversations/#{@group.id}", sent.first[:path]
  end

  test "a photo says it is a photo on the lock screen" do
    photo = Rack::Test::UploadedFile.new(StringIO.new("GIF89a"), "image/gif", true, original_filename: "kart.gif")
    sent = native_pushes_for(content: "", message_type: "text", attachment: photo)

    assert_equal I18n.t("messages.preview_photo"), sent.first[:body]
  end

  test "the job sends the words to the reader's devices through APNs" do
    NativePushToken.create!(user: @reader, token: "ab" * 32)
    delivered = []
    Apns.stub(:configured?, true) do
      Apns.stub(:deliver, ->(tokens, message) { delivered << [ tokens.map(&:user_id), message ] }) do
        NativePushJob.perform_now(user_id: @reader.id, title: "Ola", body: "Hei", path: "/conversations/1",
                                  thread: "brgen-conversation-1")
      end
    end

    assert_equal [ [ [ @reader.id ], { title: "Ola", body: "Hei", path: "/conversations/1",
                                       thread: "brgen-conversation-1" } ] ], delivered
  end
  test "a visible web device suppresses only its own endpoint for this conversation" do
    Rails.application.config.x.vapid = { subject: "mailto:a@b.c", public_key: "x", private_key: "y" }
    active = PushSubscription.create!(user: @reader, endpoint: "https://push.example/active", p256dh: "p", auth: "a")
    away = PushSubscription.create!(user: @reader, endpoint: "https://push.example/away", p256dh: "p", auth: "a")
    ChannelPresence.touch_push_device!(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: active.id
    )
    sent = []

    Webpush.stub(:payload_send, ->(**kw) { sent << kw[:endpoint] }) do
      Shared::WebPushJob.perform_now(
        @reader.id,
        title: "Ola",
        body: "Hei",
        url: "/conversations",
        conversation_id: @group.id
      )
    end

    assert_equal [ away.endpoint ], sent
    assert ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: active.id
    )
    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id + 1,
      user_id: @reader.id,
      device_type: "web",
      device_id: active.id
    )
  end

  test "leaving a web device releases only that device's push lease" do
    active = PushSubscription.create!(user: @reader, endpoint: "https://push.example/active", p256dh: "p", auth: "a")
    other = PushSubscription.create!(user: @reader, endpoint: "https://push.example/other", p256dh: "p", auth: "a")
    ChannelPresence.touch_push_device!(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: active.id
    )
    ChannelPresence.touch_push_device!(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: other.id
    )

    ChannelPresence.leave_push_device!(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: active.id
    )

    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: active.id
    )
    assert ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: other.id
    )
  end

  test "a visible native device suppresses only its own APNs token" do
    active = NativePushToken.create!(user: @reader, token: "ab" * 32)
    away = NativePushToken.create!(user: @reader, token: "cd" * 32)
    ChannelPresence.touch_push_device!(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "native",
      device_id: active.id
    )
    delivered = nil

    Apns.stub(:configured?, true) do
      Apns.stub(:deliver, ->(tokens, _message) { delivered = tokens.map(&:id) }) do
        NativePushJob.perform_now(
          user_id: @reader.id,
          conversation_id: @group.id,
          title: "Ola",
          body: "Hei",
          path: "/conversations/1",
          thread: "brgen-conversation-#{@group.id}"
        )
      end
    end

    assert_equal [ away.id ], delivered
  end

  test "an unowned push device cannot claim presence in a conversation" do
    subscription = PushSubscription.create!(
      user: @reader,
      endpoint: "https://push.example/reader",
      p256dh: "p",
      auth: "a"
    )
    post conversation_presence_path(@group), params: { device_type: "web", endpoint: subscription.endpoint }, as: :json

    assert_response :unprocessable_entity
    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @sender.id,
      device_type: "web",
      device_id: subscription.id
    )
  end

  test "the active account device can create and remove its scoped presence lease" do
    subscription = PushSubscription.create!(
      user: @sender,
      endpoint: "https://push.example/sender",
      p256dh: "p",
      auth: "a"
    )
    payload = { device_type: "web", endpoint: subscription.endpoint }

    post conversation_presence_path(@group), params: payload, as: :json
    assert_response :no_content
    assert_includes ChannelPresence.ids_for(@group), @sender.id
    assert ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @sender.id,
      device_type: "web",
      device_id: subscription.id
    )

    delete conversation_presence_path(@group), params: payload, as: :json
    assert_response :no_content
    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @sender.id,
      device_type: "web",
      device_id: subscription.id
    )
  end
  test "the browser heartbeat leases its own push endpoint and releases it when hidden" do
    source = Rails.root.join("../__shared/frontend/presence_controller.js").read

    assert_includes source, "navigator.serviceWorker.ready"
    assert_includes source, "registration.pushManager?.getSubscription()"
    assert_includes source, 'device_type: "web"'
    assert_includes source, 'document.addEventListener("visibilitychange"'
    assert_includes source, 'window.addEventListener("pagehide"'
    assert_includes source, 'this.#send("DELETE", this.#payload())'
  end

  test "a device presence lease expires without requiring an explicit unload event" do
    subscription = PushSubscription.create!(
      user: @reader, endpoint: "https://push.example/ttl",
      p256dh: "p", auth: "a"
    )
    ChannelPresence.touch_push_device!(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: subscription.id
    )

    assert ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: subscription.id
    )
    travel 46.seconds
    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @reader.id,
      device_type: "web",
      device_id: subscription.id
    )
  end
  test "the active native device can create and remove its scoped presence lease" do
    token = NativePushToken.create!(user: @sender, token: "ef" * 32)
    payload = { device_type: "native", token: token.token }

    post conversation_presence_path(@group), params: payload, as: :json
    assert_response :no_content
    assert ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @sender.id,
      device_type: "native",
      device_id: token.id
    )

    delete conversation_presence_path(@group), params: payload, as: :json
    assert_response :no_content
    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @sender.id,
      device_type: "native",
      device_id: token.id
    )
  end

  test "a different account cannot lease another account's native token" do
    token = NativePushToken.create!(user: @reader, token: "12" * 32)
    post conversation_presence_path(@group), params: { device_type: "native", token: token.token }, as: :json

    assert_response :unprocessable_entity
    assert_not ChannelPresence.push_device_active?(
      conversation_id: @group.id,
      user_id: @sender.id,
      device_type: "native",
      device_id: token.id
    )
  end
end
