import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// The stranger video room's peer wiring. The server's job is signaling only:
// this controller carries the WebRTC dance between the two browsers through
// the RandomVideoChannel, mints the media with the browser's own RTCPeerConnection
// and asks the server for TURN credentials so pairs behind hostile NATs still
// meet. Neither the SDP nor the candidate ever carries meaning to the server.
export default class extends Controller {
  static targets = ["status", "local", "remote"]
  static values = { turnUrl: String, channel: String }

  async connect() {
    this.cable = createConsumer()
    this.channel = this.cable.subscriptions.create(
      { channel: this.channelValue },
      {
        connected: () => this.start(),
        received: (message) => this.receive(message),
        disconnected: () => this.say("peer_left"),
      },
    )
  }

  disconnect() {
    this.stop()
    this.cable?.disconnect()
  }

  leave() {
    this.stop()
  }

  async start() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
      this.localTarget.srcObject = stream
      this.peer = new RTCPeerConnection({ iceServers: await this.iceServers() })
      stream.getTracks().forEach((track) => this.peer.addTrack(track, stream))
      this.peer.ontrack = (event) => { this.remoteTarget.srcObject = event.streams[0] }
      this.peer.onicecandidate = (event) => {
        if (event.candidate) this.channel.perform("relay", { type: "ice", payload: event.candidate })
      }
      this.peer.onconnectionstatechange = () => this.say(this.peer.connectionState)
      const offer = await this.peer.createOffer()
      await this.peer.setLocalDescription(offer)
      this.channel.perform("relay", { type: "offer", payload: offer })
    } catch {
      this.say("denied")
    }
  }

  async receive(message) {
    if (!this.peer || message.sender === undefined) return
    if (message.event === "peer_left") return this.say("peer_left")

    const { type, payload } = message
    if (type === "offer") {
      await this.peer.setRemoteDescription(payload)
      const answer = await this.peer.createAnswer()
      await this.peer.setLocalDescription(answer)
      this.channel.perform("relay", { type: "answer", payload: answer })
    } else if (type === "answer") {
      await this.peer.setRemoteDescription(payload)
    } else if (type === "ice") {
      await this.peer.addIceCandidate(payload)
    }
  }

  // The server's TURN REST answer needs no refresh inside one session: the
  // credential's hour outlives the stranger chat that asks for it.
  async iceServers() {
    try {
      const reply = await fetch(this.turnUrlValue)
      const { urls, username, credential } = await reply.json()
      return urls?.length ? [{ urls, username, credential }] : []
    } catch {
      return []
    }
  }

  stop() {
    this.peer?.close()
    this.peer = null
    this.localTarget.srcObject?.getTracks().forEach((track) => track.stop())
  }

  say(state) {
    this.statusTarget.textContent = state
  }
}
