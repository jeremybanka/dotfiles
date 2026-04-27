#!/usr/bin/env bun

import { execFileSync } from "node:child_process"
import { existsSync, readdirSync, statSync } from "node:fs"
import { join, resolve } from "node:path"

const helixConfigDir = resolve(
	import.meta.dirname,
	`..`,
	`home`,
	`.config`,
	`helix`
)

if (!existsSync(helixConfigDir)) {
	throw new Error(`Missing Helix config directory: ${helixConfigDir}`)
}

let reloadTimer: ReturnType<typeof setTimeout> | undefined
let lastSnapshot = snapshotTomlFiles()

console.log(`Watching Helix config files: ${helixConfigDir}`)
console.log(`Save a config or theme file to reload running hx sessions.`)

setInterval(() => {
	const nextSnapshot = snapshotTomlFiles()

	if (nextSnapshot === lastSnapshot) {
		return
	}

	lastSnapshot = nextSnapshot

	if (reloadTimer) {
		clearTimeout(reloadTimer)
	}
	reloadTimer = setTimeout(() => {
		reloadTimer = undefined
		reloadHelix()
	}, 100)
}, 500)

function snapshotTomlFiles() {
	return listTomlFiles(helixConfigDir)
		.map((path) => `${path}:${statSync(path).mtimeMs}`)
		.sort()
		.join(`\n`)
}

function listTomlFiles(dir: string): string[] {
	const paths: string[] = []

	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const path = join(dir, entry.name)
		if (entry.isDirectory()) {
			paths.push(...listTomlFiles(path))
		} else if (entry.isFile() && entry.name.endsWith(`.toml`)) {
			paths.push(path)
		}
	}

	return paths
}

function reloadHelix() {
	const pids = getHelixPids()

	if (pids.length === 0) {
		console.log(`No running hx sessions found.`)
		return
	}

	for (const pid of pids) {
		process.kill(pid, `SIGUSR1`)
	}

	console.log(
		`Reloaded ${pids.length} hx session${pids.length === 1 ? `` : `s`}.`
	)
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
