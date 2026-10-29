// Primitive server only. No Journal operations, prompts, downloads or contracts.
// The SDK's in-process core never installs process-exit handlers: Bare.exit
// would kill the entire app when running inside a mobile worklet.
import RPC from 'bare-rpc'
import os from 'bare-os'
import { Buffer } from 'bare-buffer'
import * as qvac from '@qvac/inference'
import { initialize, setConfig } from '@qvac/inference/engine'
import { llmPlugin } from '@qvac/sdk/llamacpp-completion/plugin'
import { diffusionPlugin } from '@qvac/sdk/sdcpp-generation/plugin'
const { IPC } = globalThis.BareKit
const config = JSON.parse(Bare.argv[2])
const models = new Map(), active = new Map()
const encode = value => JSON.stringify(value)
const failure = error => ({ error: { code: error?.name?.includes('Cancel') ? 'CANCELLED' : 'RESOURCE', message: 'On-device inference could not finish. Try a smaller model.', detail: `${error?.name}: ${error?.code ?? ''} ${error?.message ?? ''}` } })
let failed = false
const rpc = new RPC(IPC, async req => {
  let wire
  try {
    const p = JSON.parse(req.data.toString())
    if (failed && p.method !== '__shutdown__') throw new Error('Runtime interrupted')
    switch (p.method) {
      case 'ping': return req.reply(encode({ ok: true }))
      case 'load': {
        if (!['writing', 'image'].includes(p.task) || !p.path.startsWith('/')) throw new Error('Local model required')
        for (const [task, id] of models) { await qvac.unloadModel({ modelId: id }); models.delete(task) }
        const id = await qvac.loadModel({ modelSrc: p.path, modelType: p.task === 'image' ? 'sdcpp-generation' : 'llamacpp-completion',
          modelConfig: p.task === 'image' ? { device: os.platform() === 'android' ? 'cpu' : 'gpu', prediction: 'v', ...(os.platform() === 'android' ? { backend: 'cpu', vae_tiling: true } : {}) } : { ctx_size: 4096, device: 'cpu', verbosity: 0 } })
        models.set(p.task, id)
        return req.reply(encode({ ok: true }))
      }
      case 'unload': {
        const id = models.get(p.task)
        if (id) await qvac.unloadModel({ modelId: id })
        models.delete(p.task)
        return req.reply(encode({ ok: true }))
      }
      case 'cancel': {
        const run = active.get(p.id)
        if (run) {
          run.cancelled = true
          if (run.task === 'image') {
            const id = models.get('image'); models.delete('image')
            if (id) await qvac.unloadModel({ modelId: id })
          } else await qvac.cancel({ requestId: run.requestId })
        }
        return req.reply(encode({ ok: true }))
      }
      case 'complete': {
        if (!models.has('writing')) throw new Error('Load a writing model first')
        wire = req.createResponseStream()
        const run = qvac.completion({ modelId: models.get('writing'), history: p.messages, stream: true, kvCache: false,
          generationParams: p.params, ...(p.responseFormat ? { responseFormat: p.responseFormat } : {}) })
        const control = { requestId: run.requestId, task: 'writing', cancelled: false, wire }
        active.set(p.id, control)
        wire.on('close', () => { if (active.has(p.id)) void qvac.cancel({ requestId: run.requestId }).catch(() => {}) })
        try {
          for await (const token of run.tokenStream) {
            if (control.cancelled) break
            wire.write(encode({ type: 'token', text: token }))
          }
          const final = await run.final
          if (control.cancelled) throw Object.assign(new Error(), { name: 'Cancelled' })
          wire.write(encode({ type: 'done', outputLimit: final.stopReason === 'length' }))
        } catch (error) {
          if (control.cancelled) throw Object.assign(new Error('Generation cancelled'), { name: 'Cancelled' })
          throw error
        } finally { active.delete(p.id) }
        return wire.end()
      }
      case 'diffusion': {
        if (!models.has('image')) throw new Error('Load an image model first')
        wire = req.createResponseStream()
        const run = qvac.diffusion({ modelId: models.get('image'), prompt: p.prompt, negative_prompt: p.negativePrompt,
          width: p.width, height: p.height, steps: p.steps, seed: p.seed, cfg_scale: 7, sampling_method: 'euler_a' })
        const control = { task: 'image', cancelled: false, wire }
        active.set(p.id, control)
        try {
          for await (const tick of run.progressStream) wire.write(encode({ type: 'progress', step: tick.step, total: tick.totalSteps }))
          const [png] = await run.outputs
          if (control.cancelled) throw Object.assign(new Error(), { name: 'Cancelled' })
          wire.write(encode({ type: 'image', seed: p.seed, png: Buffer.from(png).toString('base64') }))
        } catch (error) {
          if (control.cancelled) throw Object.assign(new Error('Generation cancelled'), { name: 'Cancelled' })
          throw error
        } finally { active.delete(p.id) }
        return wire.end()
      }
      case '__shutdown__':
        for (const run of active.values()) run.cancelled = true
        await qvac.close()
        models.clear(); active.clear()
        return req.reply(encode({ ok: true }))
      default: throw new Error('Unknown primitive')
    }
  } catch (error) {
    if (wire) { wire.write(encode(failure(error))); wire.end() }
    else req.reply(encode(failure(error)))
  }
})
function fatal(error) {
  failed = true
  for (const run of active.values()) { try { run.wire.write(encode(failure(error))); run.wire.end() } catch {} }
  try { rpc.event(255).send(Buffer.from(encode(failure(error)))) } catch {}
}
Bare.on('uncaughtException', fatal)
Bare.on('unhandledRejection', fatal)

setConfig({ cacheDirectory: config.HOME_DIR + '/cache', loggerConsoleOutput: false })
initialize()
qvac.registerPlugins([llmPlugin, diffusionPlugin])
