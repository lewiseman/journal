// Execute the actual Pear stack under Bare, independently of Node's runtime.
import createTestnet from 'hyperdht/testnet.js'
import { PeopleNetwork } from './network.mjs'

const testnet = await createTestnet(3)
const options = { bootstrap: testnet.bootstrap, host: '127.0.0.1', firewalled: false }
let receive
const received = new Promise(resolve => { receive = resolve })
const alice = new PeopleNetwork({ seed: 'a'.repeat(64), name: 'Alice', options, emit: event => {
  if (event.type === 'candidate') {
    alice.configure({ friends: [event.key] })
    alice.confirm(event.key, true)
  }
} })
const bob = new PeopleNetwork({ seed: 'b'.repeat(64), name: 'Bob', options, emit: event => {
  if (event.type === 'note') receive(event)
} })
const deadline = setTimeout(() => { throw new Error('Bare P2P smoke timed out') }, 20000)
try {
  await Promise.all([alice.start(), bob.start()])
  const invite = { v: 1, key: alice.key, token: 'c'.repeat(64), expires: Date.now() + 300000 }
  alice.configure({ friends: [], invite })
  const friend = await bob.pair(invite)
  if (friend.key !== alice.key) throw new Error('Peer authentication failed')
  bob.configure({ friends: [alice.key] })
  await alice.send(bob.key, 'Temporary smoke-test note')
  const note = await received
  if (note.key !== alice.key || note.text !== 'Temporary smoke-test note') throw new Error('Invalid note')
  console.log('Bare P2P smoke passed')
} finally {
  clearTimeout(deadline)
  await Promise.all([alice.close(), bob.close()])
  await testnet.destroy()
}
