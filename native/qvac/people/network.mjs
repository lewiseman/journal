import DHT from 'hyperdht'
import b4a from 'b4a'
import sodium from 'sodium-universal'
import { Frames, frame, keyPattern, validName, validNote } from './protocol.mjs'

// No filesystem, replicated log, message mailbox or application receipts.
export class PeopleNetwork {
  constructor({ seed, name, emit = () => {}, options = {} }) {
    if (!keyPattern.test(seed) || !validName(name)) throw new Error('INVALID_IDENTITY')
    this.keyPair = DHT.keyPair(b4a.from(seed, 'hex'))
    this.key = b4a.toString(this.keyPair.publicKey, 'hex')
    this.name = name
    this.emit = emit
    this.friends = new Set()
    this.sockets = new Set()
    this.pending = new Map()
    this.invite = null
    this.closed = false
    this.node = new DHT({ ...options, keyPair: this.keyPair })
    this.node.on('error', () => {})
  }
  async start() {
    this.server = this.node.createServer({ firewall: key =>
      this.sockets.size >= 8 || (!this.friends.has(b4a.toString(key, 'hex')) && !this.activeInvite())
    }, socket => this.receive(socket))
    await this.server.listen(this.keyPair)
    return this.key
  }
  activeInvite() { return this.invite && this.invite.expires > Date.now() }
  configure({ friends, invite = null }) {
    if (!Array.isArray(friends) || friends.some(key => !keyPattern.test(key))) throw new Error('INVALID_FRIEND')
    this.friends = new Set(friends)
    this.invite = invite && keyPattern.test(invite.token) && Number.isSafeInteger(invite.expires) &&
      invite.expires <= Date.now() + 300000 ? invite : null
    for (const socket of this.sockets) {
      const key = socket.remotePublicKey && b4a.toString(socket.remotePublicKey, 'hex')
      if (key && !this.friends.has(key) && !this.activeInvite() && !this.pending.has(key)) socket.destroy()
    }
  }
  track(socket, timeout = 15000) {
    this.sockets.add(socket)
    const timer = setTimeout(() => socket.destroy(new Error('TIMEOUT')), timeout)
    socket.on('error', () => {})
    socket.on('close', () => { clearTimeout(timer); this.sockets.delete(socket) })
    return socket
  }
  receive(socket) {
    this.track(socket, 120000)
    const frames = new Frames()
    const key = b4a.toString(socket.remotePublicKey, 'hex')
    let used = false
    const firstFrame = setTimeout(() => socket.destroy(), 10000)
    socket.on('close', () => {
      clearTimeout(firstFrame)
      frames.clear()
      if (this.pending.get(key)?.socket === socket) {
        this.pending.delete(key)
        this.emit({ type: 'candidateClosed', key })
      }
    })
    socket.on('data', bytes => {
      try {
        for (const message of frames.push(bytes)) {
          if (used) throw new Error('ONE_MESSAGE_PER_CONNECTION')
          used = true
          clearTimeout(firstFrame)
          if (message.type === 'note' && this.friends.has(key) && validNote(message.text)) {
            this.emit({ type: 'note', key, text: message.text })
            socket.end()
          } else if (message.type === 'pair' && this.activeInvite() && validName(message.name) &&
              typeof message.token === 'string' && keyPattern.test(message.token) &&
              sodium.sodium_memcmp(b4a.from(message.token, 'hex'), b4a.from(this.invite.token, 'hex'))) {
            this.invite = null // Reserve the single-use token before asking for approval.
            this.pending.set(key, { socket, name: message.name.trim() })
            this.emit({ type: 'candidate', key, name: message.name.trim() })
          } else throw new Error('UNTRUSTED')
        }
      } catch { socket.destroy() }
    })
  }
  confirm(key, accepted) {
    const candidate = this.pending.get(key)
    if (!candidate) throw new Error('PAIRING_EXPIRED')
    this.pending.delete(key)
    if (!accepted) { candidate.socket.destroy(); return }
    if (!this.friends.has(key)) throw new Error('SAVE_TRUST_FIRST')
    candidate.socket.end(frame({ type: 'paired', name: this.name }))
  }
  pair(invite) {
    if (!invite || invite.v !== 1 || !keyPattern.test(invite.key) || !keyPattern.test(invite.token) ||
        invite.key === this.key || !Number.isSafeInteger(invite.expires) || invite.expires <= Date.now() ||
        invite.expires > Date.now() + 300000) throw new Error('INVALID_INVITE')
    const socket = this.track(this.node.connect(b4a.from(invite.key, 'hex'), { keyPair: this.keyPair }), 120000)
    return new Promise((resolve, reject) => {
      let settled = false
      const frames = new Frames()
      socket.on('open', () => socket.write(frame({ type: 'pair', token: invite.token, name: this.name })))
      socket.on('data', bytes => {
        try {
          for (const message of frames.push(bytes)) {
            if (settled || message.type !== 'paired' || !validName(message.name) ||
                b4a.toString(socket.remotePublicKey, 'hex') !== invite.key) throw new Error('INVALID_PAIR')
            settled = true
            resolve({ key: invite.key, name: message.name.trim() })
            socket.end()
          }
        } catch { socket.destroy() }
      })
      socket.on('close', () => { frames.clear(); if (!settled) reject(new Error('PAIRING_FAILED')) })
    })
  }
  send(key, text) {
    if (!this.friends.has(key) || !validNote(text)) throw new Error('INVALID_NOTE')
    const packet = frame({ type: 'note', text })
    const socket = this.track(this.node.connect(b4a.from(key, 'hex'), { keyPair: this.keyPair }))
    return new Promise((resolve, reject) => {
      let written = false
      socket.on('finish', () => {
        written = true
        resolve({ attempted: true }) // Local stream finish, never a delivery receipt.
      })
      socket.on('open', () => {
        if (!this.friends.has(key)) { socket.destroy(); return }
        socket.end(packet)
      })
      socket.on('close', () => { if (!written) reject(new Error('SEND_FAILED')) })
    })
  }
  async close() {
    this.closed = true
    this.emit = () => {}
    this.invite = null
    this.pending.clear()
    for (const socket of this.sockets) socket.destroy()
    this.friends.clear()
    await this.node.destroy({ force: true })
    this.keyPair.secretKey.fill(0)
  }
}
