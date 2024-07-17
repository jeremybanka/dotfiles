#!/usr/bin/env bun

import { existsSync, lstatSync, symlink, unlink } from "node:fs"
import { homedir } from "node:os"
import { join, resolve } from "node:path"
import { promisify } from "node:util"

const symlinkAsync = promisify(symlink)
const unlinkAsync = promisify(unlink)
const appConfigDir = join(import.meta.dirname, `..`, `apps`)

await configureVSCodium()

async function configureVSCodium() {
	const sourcePath = resolve(appConfigDir, `VSCodium`, `settings.json`)
	const targetPath = join(
		homedir(),
		`Library`,
		`Application Support`,
		`VSCodium`,
		`User`,
		`settings.json`
	)
	console.log(`Configuring VSCodium`, { appConfigDir, sourcePath, targetPath })
	try {
		if (!existsSync(sourcePath)) {
			throw new Error(`Source file does not exist: ${sourcePath}`)
		}

		if (existsSync(targetPath)) {
			const isSymlink = lstatSync(targetPath).isSymbolicLink()
			if (isSymlink) {
				console.log(`Symlink already exists: ${targetPath}`)
				return
			} else {
				console.log(`Removing existing file: ${targetPath}`)
				await unlinkAsync(targetPath)
			}
		}

		await symlinkAsync(sourcePath, targetPath)
		console.log(`Symlink created: ${sourcePath} -> ${targetPath}`)
	} catch (thrown) {
		if (thrown instanceof Error) {
			console.error(thrown.message)
		} else {
			console.error(thrown)
		}
	}
}
