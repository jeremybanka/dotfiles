#!/usr/bin/env bun

import { execFileSync } from "node:child_process"
import {
	lstatSync,
	mkdirSync,
	readFileSync,
	unlinkSync,
	writeFileSync,
} from "node:fs"
import { dirname, join, resolve } from "node:path"

const label = `com.jeremybanka.helix-theme`
const home = process.env.HOME

if (!home) {
	throw new Error(`HOME is not set`)
}

const installDir = resolve(home, `.local`, `libexec`, label)
const launchAgentsDir = resolve(home, `Library`, `LaunchAgents`)
const logsDir = resolve(home, `Library`, `Logs`)
const templatePath = join(import.meta.dirname, `${label}.plist.template`)
const plistPath = join(launchAgentsDir, `${label}.plist`)
const replacements = {
	BUN: execFileSync(`command`, [`-v`, `bun`], { encoding: `utf8` }).trim(),
	STDERR_LOG: join(logsDir, `${label}.err.log`),
	STDOUT_LOG: join(logsDir, `${label}.out.log`),
	THEME_SWITCHER: join(installDir, `theme-switcher.ts`),
}

let plist = readFileSync(templatePath, `utf8`)

for (const [name, value] of Object.entries(replacements)) {
	plist = plist.replaceAll(`{{${name}}}`, value)
}

mkdirSync(dirname(plistPath), { recursive: true })
mkdirSync(logsDir, { recursive: true })

try {
	const existingPlist = lstatSync(plistPath)
	if (existingPlist.isSymbolicLink()) {
		unlinkSync(plistPath)
	}
} catch {
	// No existing plist to replace.
}

writeFileSync(plistPath, plist)
console.log(plistPath)
