import b4a from 'b4a'

export const MAX_FRAME = 16 * 1024
export const keyPattern = /^[a-f0-9]{64}$/
export const wordCount = text => text.trim() ? text.trim().split(/\s+/u).length : 0
export function validNote(text) {
  return typeof text === 'string' && text.trim().length > 0 &&
    wordCount(text) <= 500 && b4a.byteLength(text, 'utf8') <= 8192
}
export function validName(name) {
  return typeof name === 'string' && name.trim().length > 0 && name.length <= 80
}
export function frame(value) {
  const body = b4a.from(JSON.stringify({ ...value, v: 1 }))
  if (!body.length || body.length > MAX_FRAME) throw new Error('INVALID_FRAME')
  const header = b4a.alloc(4)
  b4a.writeUInt32BE(header, body.length, 0)
  return b4a.concat([header, body])
}

// Noise exposes a byte stream: a read is not necessarily one message.
export class Frames {
  constructor() { this.buffer = b4a.alloc(0) }
  push(chunk) {
    if (chunk.length > MAX_FRAME + 4) throw new Error('INVALID_FRAME')
    this.buffer = b4a.concat([this.buffer, chunk])
    const values = []
    while (this.buffer.length >= 4) {
      const size = b4a.readUInt32BE(this.buffer, 0)
      if (!size || size > MAX_FRAME) throw new Error('INVALID_FRAME')
      if (this.buffer.length < size + 4) break
      const raw = b4a.toString(this.buffer.subarray(4, size + 4), 'utf8')
      const value = JSON.parse(raw)
      if (!value || value.v !== 1 || typeof value.type !== 'string') throw new Error('INVALID_FRAME')
      values.push(value)
      this.buffer = this.buffer.subarray(size + 4)
    }
    if (this.buffer.length > MAX_FRAME + 4) throw new Error('INVALID_FRAME')
    return values
  }
  clear() { this.buffer = b4a.alloc(0) }
}
