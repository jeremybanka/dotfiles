#!/usr/bin/env bun

import { execFileSync } from "node:child_process"
import {
	existsSync,
	lstatSync,
	readlinkSync,
	symlinkSync,
	unlinkSync,
} from "node:fs"
import { join, resolve } from "node:path"

const helixConfigDir = resolve(
	import.meta.dirname,
	`..`,
	`home`,
	`.config`,
	`helix`
)
const activeConfigPath = join(helixConfigDir, `config.toml`)

const shouldWatch = process.argv.includes(`--watch`)

let lastMode = syncHelixTheme()

if (shouldWatch) {
	console.log(`Watching macOS appearance for Helix theme changes.`)

	setInterval(() => {
		const nextMode = getMacOSAppearance()
		if (nextMode === lastMode) {
			return
		}

		lastMode = syncHelixTheme()
		reloadHelix()
	}, 5000)
} else {
	console.log(`Helix is using ${lastMode} mode.`)
}

function syncHelixTheme() {
	const mode = getMacOSAppearance()
	const sourceName = mode === `dark` ? `config.dark.toml` : `config.light.toml`
	const sourcePath = join(helixConfigDir, sourceName)

	if (!existsSync(sourcePath)) {
		throw new Error(`Missing Helix ${mode} config: ${sourcePath}`)
	}

	if (existsSync(activeConfigPath)) {
		const activeStat = lstatSync(activeConfigPath)
		if (!activeStat.isSymbolicLink()) {
			throw new Error(
				`Refusing to replace non-symlink Helix config: ${activeConfigPath}`
			)
		}

		if (readlinkSync(activeConfigPath) === sourceName) {
			return mode
		}

		unlinkSync(activeConfigPath)
	}

	symlinkSync(sourceName, activeConfigPath)
	console.log(`Helix now uses ${mode} mode via ${sourceName}.`)
	return mode
}

function getMacOSAppearance() {
	try {
		const output = execFileSync(
			`defaults`,
			[`read`, `-g`, `AppleInterfaceStyle`],
			{
				encoding: `utf8`,
				stdio: [`ignore`, `pipe`, `ignore`],
			}
		).trim()

		return output === `Dark` ? `dark` : `light`
	} catch {
		return `light`
	}
}

function reloadHelix() {
	for (const pid of getHelixPids()) {
		process.kill(pid, `SIGUSR1`)
	}
}

function getHelixPids() {
	const pidSet = new Set<number>()

	for (const processName of [`hx`, `helix-term`]) {
		try {
			const output = execFileSync(`pgrep`, [`-x`, processName], {
				encoding: `utf8`,
				stdio: [`ignore`, `pipe`, `ignore`],
			}).trim()

			for (const line of output.split(`\n`)) {
				const pid = Number(line)
				if (Number.isInteger(pid)) {
					pidSet.add(pid)
				}
			}
		} catch {
			// No matching process for this name.
		}
	}

	return [...pidSet]
}
