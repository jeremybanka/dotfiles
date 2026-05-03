#!/usr/bin/env bun

import { spawn } from "node:child_process"
import { resolve } from "node:path"

type JsonRpcMessage = {
	id?: number | string
	method?: string
	params?: unknown
	result?: unknown
	error?: unknown
	jsonrpc: `2.0`
}

type TextDocumentIdentifier = {
	uri: string
	version?: number
}

type DiagnosticReport = {
	items?: unknown[]
	kind?: string
}

type CodeAction = {
	edit?: {
		changes?: Record<string, unknown[]>
		documentChanges?: {
			edits?: unknown[]
			textDocument?: TextDocumentIdentifier
		}[]
	}
}

const projectRoot = resolve(import.meta.dirname, `..`, `..`)

const server = spawn(
	`/opt/homebrew/bin/node`,
	[`./node_modules/.bin/vscode-eslint-language-server`, `--stdio`],
	{
		cwd: projectRoot,
		stdio: [`pipe`, `pipe`, `pipe`],
	}
)

const openDocuments = new Map<string, TextDocumentIdentifier>()
const pendingRefreshes = new Map<string, ReturnType<typeof setTimeout>>()
const diagnosticRequests = new Map<number | string, TextDocumentIdentifier>()
const serverRequests = new Map<
	number | string,
	{
		reject: (error: unknown) => void
		resolve: (result: unknown) => void
	}
>()
let nextDiagnosticRequestId = 1
let nextServerRequestId = 1

server.stderr.on(`data`, (chunk) => {
	process.stderr.write(chunk)
})

server.on(`exit`, (code, signal) => {
	for (const timeout of pendingRefreshes.values()) {
		clearTimeout(timeout)
	}

	if (signal) {
		process.exit(1)
	}

	process.exit(code ?? 1)
})

readMessages(process.stdin, (message) => {
	void handleClientMessage(message).then((handled) => {
		if (!handled) {
			writeMessage(server.stdin, message)
		}
	})
})

readMessages(server.stdout, (message) => {
	if (handleServerMessage(message)) {
		return
	}

	writeMessage(process.stdout, message)
})

async function handleClientMessage(message: JsonRpcMessage) {
	if (message.method === `textDocument/didOpen`) {
		const textDocument = getTextDocument(message.params)
		if (textDocument) {
			openDocuments.set(textDocument.uri, textDocument)
			scheduleDiagnosticRefresh(textDocument)
		}
	} else if (message.method === `textDocument/didChange`) {
		const textDocument = getTextDocument(message.params)
		if (textDocument) {
			openDocuments.set(textDocument.uri, {
				...openDocuments.get(textDocument.uri),
				...textDocument,
			})
			scheduleDiagnosticRefresh(textDocument)
		}
	} else if (message.method === `textDocument/didSave`) {
		const textDocument = getTextDocument(message.params)
		if (textDocument) {
			scheduleDiagnosticRefresh(
				openDocuments.get(textDocument.uri) ?? textDocument
			)
		}
	} else if (message.method === `textDocument/didClose`) {
		const textDocument = getTextDocument(message.params)
		if (textDocument) {
			openDocuments.delete(textDocument.uri)
			clearDiagnosticRefresh(textDocument.uri)
			publishDiagnostics(textDocument, [])
		}
	} else if (message.method === `textDocument/willSaveWaitUntil`) {
		const textDocument = getTextDocument(message.params)
		if (message.id === undefined || !textDocument) {
			return false
		}

		const edits = await fixAll(textDocument)
		writeMessage(process.stdout, {
			jsonrpc: `2.0`,
			id: message.id,
			result: edits,
		})
		return true
	}

	return false
}

function handleServerMessage(message: JsonRpcMessage) {
	if (message.id !== undefined && serverRequests.has(message.id)) {
		const request = serverRequests.get(message.id)
		serverRequests.delete(message.id)

		if (message.error) {
			request?.reject(message.error)
		} else {
			request?.resolve(message.result)
		}

		return true
	}

	if (isInitializeResult(message)) {
		message.result.capabilities.textDocumentSync.willSaveWaitUntil = true
		message.result.capabilities.documentFormattingProvider = true
		return false
	}

	if (message.id === undefined || !diagnosticRequests.has(message.id)) {
		return false
	}

	const textDocument = diagnosticRequests.get(message.id)
	diagnosticRequests.delete(message.id)

	if (!textDocument || message.error) {
		return true
	}

	const report = message.result as DiagnosticReport
	publishDiagnostics(textDocument, report.items ?? [])
	return true
}

async function fixAll(textDocument: TextDocumentIdentifier) {
	try {
		const diagnostics = await getDiagnostics(textDocument)
		publishDiagnostics(textDocument, diagnostics)

		const actions = (await sendServerRequest(`textDocument/codeAction`, {
			textDocument: { uri: textDocument.uri },
			range: {
				start: { line: 0, character: 0 },
				end: { line: 0, character: 0 },
			},
			context: {
				diagnostics,
				only: [`source.fixAll.eslint`],
				triggerKind: 1,
			},
		})) as CodeAction[]

		return getTextEdits(textDocument.uri, actions[0])
	} catch (error) {
		console.error(`Failed to apply ESLint fixes on save:`, error)
		return []
	}
}

function scheduleDiagnosticRefresh(textDocument: TextDocumentIdentifier) {
	clearDiagnosticRefresh(textDocument.uri)

	pendingRefreshes.set(
		textDocument.uri,
		setTimeout(() => {
			pendingRefreshes.delete(textDocument.uri)
			requestDiagnostics(openDocuments.get(textDocument.uri) ?? textDocument)
		}, 200)
	)
}

function clearDiagnosticRefresh(uri: string) {
	const timeout = pendingRefreshes.get(uri)
	if (!timeout) {
		return
	}

	clearTimeout(timeout)
	pendingRefreshes.delete(uri)
}

function requestDiagnostics(textDocument: TextDocumentIdentifier) {
	const id = `eslint-pull-diagnostics-${nextDiagnosticRequestId++}`
	diagnosticRequests.set(id, textDocument)

	writeMessage(server.stdin, {
		jsonrpc: `2.0`,
		id,
		method: `textDocument/diagnostic`,
		params: {
			textDocument: { uri: textDocument.uri },
			previousResultId: null,
		},
	})
}

async function getDiagnostics(textDocument: TextDocumentIdentifier) {
	const report = (await sendServerRequest(`textDocument/diagnostic`, {
		textDocument: { uri: textDocument.uri },
		previousResultId: null,
	})) as DiagnosticReport

	return report.items ?? []
}

function sendServerRequest(method: string, params: unknown) {
	const id = `eslint-proxy-${nextServerRequestId++}`

	writeMessage(server.stdin, {
		jsonrpc: `2.0`,
		id,
		method,
		params,
	})

	return new Promise((complete, reject) => {
		serverRequests.set(id, { reject, resolve: complete })
	})
}

function publishDiagnostics(
	textDocument: TextDocumentIdentifier,
	diagnostics: unknown[]
) {
	writeMessage(process.stdout, {
		jsonrpc: `2.0`,
		method: `textDocument/publishDiagnostics`,
		params: {
			uri: textDocument.uri,
			version: textDocument.version,
			diagnostics,
		},
	})
}

function getTextDocument(params: unknown): TextDocumentIdentifier | undefined {
	if (!params || typeof params !== `object`) {
		return undefined
	}

	const textDocument = (params as { textDocument?: unknown }).textDocument
	if (!textDocument || typeof textDocument !== `object`) {
		return undefined
	}

	const { uri, version } = textDocument as TextDocumentIdentifier
	if (typeof uri !== `string`) {
		return undefined
	}

	return {
		uri,
		version: typeof version === `number` ? version : undefined,
	}
}

function getTextEdits(uri: string, action?: CodeAction) {
	if (!action?.edit) {
		return []
	}

	const changes = action.edit.changes?.[uri]
	if (changes) {
		return changes
	}

	const documentChange = action.edit.documentChanges?.find(
		(change) => change.textDocument?.uri === uri
	)
	return documentChange?.edits ?? []
}

function isInitializeResult(
	message: JsonRpcMessage
): message is JsonRpcMessage & {
	result: {
		capabilities: {
			documentFormattingProvider?: boolean
			textDocumentSync: { willSaveWaitUntil?: boolean }
		}
	}
} {
	if (!message.result || typeof message.result !== `object`) {
		return false
	}

	const capabilities = (message.result as { capabilities?: unknown })
		.capabilities
	if (!capabilities || typeof capabilities !== `object`) {
		return false
	}

	const textDocumentSync = (capabilities as { textDocumentSync?: unknown })
		.textDocumentSync
	return !!textDocumentSync && typeof textDocumentSync === `object`
}

function readMessages(
	stream: NodeJS.ReadableStream,
	onMessage: (message: JsonRpcMessage) => void
) {
	let buffer = Buffer.alloc(0)

	stream.on(`data`, (chunk: Buffer) => {
		buffer = Buffer.concat([buffer, chunk])

		while (true) {
			const headerEnd = buffer.indexOf(`\r\n\r\n`)
			if (headerEnd === -1) {
				return
			}

			const header = buffer.subarray(0, headerEnd).toString()
			const contentLength = Number(/^Content-Length: (\d+)$/im.exec(header)?.[1])
			const bodyStart = headerEnd + 4

			if (
				!Number.isFinite(contentLength) ||
				buffer.length < bodyStart + contentLength
			) {
				return
			}

			const body = buffer
				.subarray(bodyStart, bodyStart + contentLength)
				.toString()
			buffer = buffer.subarray(bodyStart + contentLength)
			onMessage(JSON.parse(body) as JsonRpcMessage)
		}
	})
}

function writeMessage(stream: NodeJS.WritableStream, message: JsonRpcMessage) {
	const body = Buffer.from(JSON.stringify(message))
	stream.write(`Content-Length: ${body.length}\r\n\r\n`)
	stream.write(body)
}
