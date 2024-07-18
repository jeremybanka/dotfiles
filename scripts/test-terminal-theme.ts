#! bun

function printColorSpecimens() {
	const colors: { [key: string]: string } = {
		"Black": `\x1b[30m`,
		"Red": `\x1b[31m`,
		"Green": `\x1b[32m`,
		"Yellow": `\x1b[33m`,
		"Blue": `\x1b[34m`,
		"Magenta": `\x1b[35m`,
		"Cyan": `\x1b[36m`,
		"White": `\x1b[37m`,
		"Bright Black": `\x1b[90m`,
		"Bright Red": `\x1b[91m`,
		"Bright Green": `\x1b[92m`,
		"Bright Yellow": `\x1b[93m`,
		"Bright Blue": `\x1b[94m`,
		"Bright Magenta": `\x1b[95m`,
		"Bright Cyan": `\x1b[96m`,
		"Bright White": `\x1b[97m`,
	}

	for (const [colorName, colorCode] of Object.entries(colors)) {
		console.log(`${colorCode}${colorName}\x1b[0m`)
	}
}

printColorSpecimens()
