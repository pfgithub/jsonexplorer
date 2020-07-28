https://github.com/chromium/hterm/blob/master/doc/ControlSequences.md ← use this it's actually helpful

### sent ctrl sequences

- `\x1b[?1049h\x1b[22;0;0t\x1b[2J\x1b[H` - enter fullscreen (a seperate, cleared terminal screen)
- `\x1b[2J\x1b[H\x1b[?1049l\x1b[23;0;0t` - exit fullscreen (restores the previous screen. like how when you exit vim, all your commands are still there)

### recieved ctrl sequences

- `\x03`: `ctrl+c`
- `\x04`: `ctrl+d`
- `26`: `ctrl+z`
- `\x1b`:
	- `[`:
		- `2`: `~`: `insert`
		- `3`: `~`: `delete`
		- `A`: `↑`
		- `B`: `↓`
		- `C`: `→`
		- `D`: `←`
		- `<`: (for mouse mode 1003;1015;1006h)
			- (\[0-9\]+ data)`;`(\[0-9\]+ x)`;`(\[0-9\]+ y)(`M`/`m` direction)
				- direction: `M`: mouse down or mouse move, `m`: mouse up
				- data: lsb…(u2 btn)(u1 shift)(u1 alt)(u1 ctrl)(u1 prsres)(u1 scroll)(u1 unused)…msb
					- btn: 0 left, 1 middle, 2 right, 3 none
					- shift/alt/ctrl: booleans if the key is pressed
					- prsres: boolean true if the mouse is being moved, false on click eg
					- scroll: bool if true, btn 0 = scroll up, btn 1 = scroll down now
		- `M`: (for mouse mode 1003;1015;1015h)
			- (byte b) (byte x) (byte y)
				- b: least significant…(u2 btn)(u1 shift)(u1 meta)(u1 ctrl)(u3 rest)…most significant
				- x/y: subtract 33
				- btn: 0: left, 1: middle, 2: right, 3: none
				- rest:
					- 1: on button press/release
					- 2: on mouse movement
					- 3: scroll. now btn is 0: scroll up, 1: scroll down.