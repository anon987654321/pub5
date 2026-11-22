# frozen_string_literal: true

# Heartbeat endpoint for "who has this room open".
#
# Mirrors TypingIndicatorsController: nested under a conversation, create-only,
# fire-and-forget. head :no_content rather than a body -- the count reaches every
# reader over the conversation's Turbo stream, so the beat itself has nothing to
# say back and shouldn't pay for a render 3x a minute per reader.
class PresencesController < ApplicationController
  before_action :require_user_session
  before_action :set_conversation

  def create
    if device_request?
      touched = with_owned_device do |type, id|
        ChannelPresence.touch_push_device!(
          conversation_id: @conversation.id, user_id: Current.user.id, device_type: type, device_id: id
        )
      end
      return head :unprocessable_entity unless touched

    end

    # Keep the conversation roster current as well as the device's push lease.
    # The device key is separate, so push can be suppressed on one endpoint
    # without treating another endpoint as open.
    ChannelPresence.touch!(conversation: @conversation, user: Current.user)
    head :no_content
  end

  # Device leases are independent, so leaving on one screen never removes
  # another screen's active lease.
  def destroy
    if device_request?
      with_owned_device do |type, id|
        ChannelPresence.leave_push_device!(
          conversation_id: @conversation.id, user_id: Current.user.id, device_type: type, device_id: id
        )
      end
    else
      ChannelPresence.leave!(conversation: @conversation, user: Current.user)
    end
    head :no_content
  end

  private

  # Scoped through the participant join, exactly as TypingIndicatorsController
  # does it. An unscoped Conversation.find let anyone who knew a conversation id
  # beat into a room they are not in — and since the beat broadcasts the roster
  # to every reader, that showed a stranger as present in a private thread.
  def device_request? = params[:device_type].present?

  # Resolve the browser endpoint / APNs token through the current user's own
  # rows. A caller cannot lease another account's device, and raw credentials
  # are never written to the cache.
  def with_owned_device
    record = case params[:device_type].to_s
             when "web"
               endpoint = params[:endpoint].to_s
               return false if endpoint.empty? || endpoint.bytesize > 4096
               Current.user.push_subscriptions.find_by(endpoint: endpoint)
             when "native"
               token = params[:token].to_s.downcase
               return false unless token.match?(/\A\h{64,200}\z/)
               Current.user.native_push_tokens.find_by(token: token)
             end
    return false unless record

    yield(params[:device_type].to_s, record.id)
  end

  def set_conversation
    @conversation = Conversation.for_user(Current.user).find(params[:conversation_id])
  end
end
