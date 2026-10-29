import { test } from 'node:test'
import assert from 'node:assert/strict'
import { randomBytes } from 'node:crypto'
import createTestnet from 'hyperdht/testnet.js'
import { PeopleNetwork } from './network.mjs'
import { Frames, frame, validNote } from './protocol.mjs'

test('framing accepts fragments and coalesced frames; rejects oversized and malformed input', () => {
  const parser = new Frames(), packet = frame({ type: 'note', text: 'hello 🌿' })
  assert.deepEqual(parser.push(packet.subarray(0, 2)), [])
  assert.deepEqual(parser.push(packet.subarray(2, 9)), [])
  assert.equal(parser.push(packet.subarray(9))[0].text, 'hello 🌿')
  assert.equal(new Frames().push(Buffer.concat([packet, packet])).length, 2)
  assert.throws(() => new Frames().push(Buffer.from([0, 1, 0, 0])))
  assert.throws(() => new Frames().push(Buffer.concat([Buffer.from([0, 0, 0, 1]), Buffer.from('!')])))
  assert.equal(validNote('word '.repeat(501)), false)
  assert.equal(validNote('🌿'.repeat(3000)), false)
  assert.equal(validNote('   '), false)
})

test('real Noise peers pair, exchange a note, reject stale invites and revoke trust', { timeout: 30000 }, async t => {
  const testnet = await createTestnet(3)
  t.after(() => testnet.destroy())
  const options = { bootstrap: testnet.bootstrap, host: '127.0.0.1', firewalled: false }
  const aliceEvents = [], bobEvents = []
  const alice = new PeopleNetwork({ seed: randomBytes(32).toString('hex'), name: 'Alice', options, emit: e => aliceEvents.push(e) })
  const bob = new PeopleNetwork({ seed: randomBytes(32).toString('hex'), name: 'Bob', options, emit: e => bobEvents.push(e) })
  t.after(() => Promise.all([alice.close(), bob.close()]))
  await Promise.all([alice.start(), bob.start()])
  const invite = { v: 1, key: alice.key, token: randomBytes(32).toString('hex'), expires: Date.now() + 300000 }
  alice.configure({ friends: [], invite })
  const paired = bob.pair(invite)
  const deadline = Date.now() + 10000
  while (!aliceEvents.some(e => e.type === 'candidate') && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 10))
  }
  assert.equal(aliceEvents.find(e => e.type === 'candidate')?.key, bob.key)
  assert.equal(alice.activeInvite(), null)
  alice.configure({ friends: [bob.key] })
  alice.confirm(bob.key, true)
  assert.deepEqual(await paired, { key: alice.key, name: 'Alice' })
  bob.configure({ friends: [alice.key] })
  await alice.send(bob.key, 'One brief note')
  const noteDeadline = Date.now() + 3000
  while (!bobEvents.some(e => e.type === 'note') && Date.now() < noteDeadline) {
    await new Promise(resolve => setTimeout(resolve, 10))
  }
  assert.equal(bobEvents.find(e => e.type === 'note')?.text, 'One brief note')
  await assert.rejects(bob.pair(invite)) // A consumed token cannot pair again.
  assert.throws(() => bob.pair({ ...invite, expires: Date.now() - 1 }))
  bob.configure({ friends: [] })
  assert.throws(() => bob.send(alice.key, 'no longer trusted'))
})
