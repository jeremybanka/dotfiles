#!bun

import { homedir } from "node:os"
import { join } from "node:path"

import { $ } from "bun"

await installNpmGlobals()

async function installNpmGlobals() {
	const globalPackageDir = join(homedir(), `.bun`, `install`, `global`)
	for (const filename of [`package.json`, `bun.lockb`]) {
		const targetPath = join(globalPackageDir, filename)
		console.log(`Installing npm globals`, { targetPath })
		try {
			await $`cd ${globalPackageDir} && bun install`
		} catch (thrown) {
			if (thrown instanceof Error) {
				console.error(thrown.message)
			} else {
				console.error(thrown)
			}
		}
	}
}
