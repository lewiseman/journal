import RPC from 'bare-rpc'
import { PeopleNetwork } from './network.mjs'

const { IPC } = globalThis.BareKit
let network, events
const rpc = new RPC(IPC, async request => {
  try {
    const input = JSON.parse(request.data.toString())
    let result = { ok: true }
    switch (input.method) {
      case 'ping': break
      case 'events':
        events?.end()
        events = request.createResponseStream()
        return
      case 'start':
        await network?.close()
        network = new PeopleNetwork({ ...input, emit: event => events?.write(JSON.stringify(event)) })
        result = { key: await network.start() }
        break
      case 'configure': network.configure(input); break
      case 'pair': result = await network.pair(input.invite); break
      case 'confirm': network.confirm(input.key, input.accepted); break
      case 'send': result = await network.send(input.key, input.text); break
      case '__shutdown__':
        await network?.close()
        network = null
        events?.end(); events = null
        break
      default: throw new Error('INVALID_METHOD')
    }
    request.reply(JSON.stringify(result))
  } catch {
    // Never forward exception detail, note text, keys or invitations to logs.
    request.reply(JSON.stringify({ error: 'PEOPLE_UNAVAILABLE' }))
  }
})
Bare.on('uncaughtException', () => { void network?.close(); events?.end() })
Bare.on('unhandledRejection', () => { void network?.close(); events?.end() })
