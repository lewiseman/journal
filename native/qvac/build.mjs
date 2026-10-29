// Adapts qvac_flutter's Apache-2.0 BareKit build. Generated resources are owned
// exclusively by this adapter; model weights never enter the app bundle.
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import link from 'bare-link'
import { bundleSdk } from '@qvac/sdk/commands'
const root = import.meta.dirname, app = path.resolve(root, '../..'), require = createRequire(import.meta.url)
let gemHome = process.env.QVAC_GEM_HOME
if (!gemHome) {
  for (const pod of ['/opt/homebrew/bin/pod', '/usr/local/bin/pod']) {
    if (!existsSync(pod)) continue
    const wrapper = await readFile(pod, 'utf8')
    gemHome = wrapper.match(/GEM_HOME="([^"]+)"/)?.[1]
    if (gemHome) break
  }
}
const hosts = { ios: ['ios-arm64', 'ios-arm64-simulator'], android: ['android-arm64'] }
const platforms = process.platform === 'darwin' ? Object.keys(hosts) : ['android']
const sdkPath = path.dirname(require.resolve('@qvac/sdk/package'))
await bundleSdk({ projectRoot: root, hosts: platforms.flatMap(p => hosts[p]), installMissingPrebuilds: true })
const bundleFile = path.join(root, 'qvac/primitive.bundle')
execFileSync(process.execPath, [path.join(root, 'node_modules/bare-pack/bin.js'),
  ...platforms.flatMap(p => hosts[p]).flatMap(h => ['--host', h]), '--linked', '--imports', path.join(sdkPath, 'bare-imports.json'),
  '--out', bundleFile, path.join(root, 'entry.mjs')], { stdio: 'inherit' })
const bundle = await readFile(bundleFile)
for (const platform of platforms) {
  const out = path.join(root, 'qvac', platform, 'addons')
  await rm(out, { recursive: true, force: true })
  for await (const _ of link(path.join(root, 'entry.mjs'), { hosts: hosts[platform], out }));
}
const url = 'https://github.com/holepunchto/bare-kit/releases/download/v2.5.5/prebuilds.zip'
const expected = 'fc68740347c8532ba49d45bf61fae9ca1f1040dc7d6c99f2f92dc30c40e84e46'
const cache = path.join(root, 'cache'), zip = path.join(cache, 'bare-kit.zip'), kit = path.join(cache, 'bare-kit')
await mkdir(cache, { recursive: true })
if (!existsSync(zip)) {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`BareKit download failed: ${response.status}`)
  await writeFile(zip, Buffer.from(await response.arrayBuffer()))
}
if (createHash('sha256').update(await readFile(zip)).digest('hex') !== expected) {
  await rm(zip); throw new Error('BareKit checksum mismatch; archive discarded')
}
if (!existsSync(kit)) execFileSync('unzip', ['-q', zip, 'ios/*', 'android/*', '-d', kit])
const android = path.join(app, 'android/app/src/qvac')
await rm(android, { recursive: true, force: true })
await mkdir(path.join(android, 'libs'), { recursive: true })
await cp(path.join(root, 'qvac/android/addons'), path.join(android, 'jniLibs'), { recursive: true })
await cp(path.join(kit, 'android/bare-kit/jni/arm64-v8a'), path.join(android, 'jniLibs/arm64-v8a'), { recursive: true })
await cp(path.join(kit, 'android/bare-kit/classes.jar'), path.join(android, 'libs/bare-kit.jar'))
await mkdir(path.join(android, 'assets'), { recursive: true })
await writeFile(path.join(android, 'assets/worker.bundle'), bundle)
if (platforms.includes('ios')) {
  const frameworks = path.join(app, 'ios/Frameworks/Qvac')
  await rm(frameworks, { recursive: true, force: true })
  await cp(path.join(root, 'qvac/ios/addons'), frameworks, { recursive: true })
  await cp(path.join(kit, 'ios/BareKit.xcframework'), path.join(frameworks, 'BareKit.xcframework'), { recursive: true })
  for (const slice of ['ios-arm64', 'ios-arm64_x86_64-simulator']) {
    const dir = path.join(frameworks, 'BareKit.xcframework', slice, 'BareKit.framework/Modules')
    await mkdir(dir, { recursive: true })
    await writeFile(path.join(dir, 'module.modulemap'), 'framework module BareKit { umbrella header "BareKit.h" export * module * { export * } }\n')
  }
  await mkdir(path.join(app, 'ios/Runner/Qvac'), { recursive: true })
  await writeFile(path.join(app, 'ios/Runner/Qvac/worker.bundle'), bundle)
  execFileSync(process.env.QVAC_RUBY || (existsSync('/opt/homebrew/bin/ruby') ? '/opt/homebrew/bin/ruby' : 'ruby'), [path.join(root, 'wire-ios.rb'), app], { stdio: 'inherit', env: { ...process.env, ...(gemHome ? { GEM_HOME: gemHome } : {}) } })
}
// Preserve every package's license and notices alongside a machine-readable SBOM.
const packages = []
async function licenses(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue
    const folder = path.join(dir, entry.name)
    if (entry.name.startsWith('@')) { await licenses(folder); continue }
    if (!existsSync(path.join(folder, 'package.json'))) continue
    const pkg = JSON.parse(await readFile(path.join(folder, 'package.json'), 'utf8'))
    packages.push({ name: pkg.name, version: pkg.version, license: pkg.license })
    for (const file of await readdir(folder)) if (/^(licen[cs]e|notice|copying)(\.|$)/i.test(file)) {
      const target = path.join(root, 'qvac/licenses', pkg.name.replaceAll('/', '_'), file)
      await mkdir(path.dirname(target), { recursive: true }); await cp(path.join(folder, file), target)
    }
  }
}
await licenses(path.join(root, 'node_modules'))
await mkdir(path.join(root, 'qvac/licenses/qvac_flutter'), { recursive: true })
for (const name of ['LICENSE', 'NOTICE']) await cp(path.join(app, 'lib/modules/local_ai/engines/qvac', name), path.join(root, 'qvac/licenses/qvac_flutter', name))
await writeFile(path.join(root, 'qvac/licenses/packages.json'), JSON.stringify(packages, null, 2))
await cp(path.join(root, 'qvac/licenses'), path.join(android, 'assets/qvac-licenses'), { recursive: true })
console.log(`QVAC primitives built for ${platforms.join(', ')}. Weights are downloaded only at runtime.`)

if (platforms.includes('ios')) await cp(path.join(root, 'qvac/licenses'), path.join(app, 'ios/Runner/Qvac/licenses'), { recursive: true })
