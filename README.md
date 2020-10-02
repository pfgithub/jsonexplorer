# Now merged into [zcho](https://github.com/pfgithub/zcho) `z jsonexplorer`

# jsonexplorer

```bash
zig targets | zig build run
```

![screenshot](https://media.discordapp.net/attachments/605572611539206171/747581462777299104/Peek_2020-08-24_15-21.gif)

## other stuff

also contains some things for debugging terminal escape codes:

```
zig build escape && zig-cache/bin/escape_sequence_debug --event --mouse
```

- `--event` chooses whether to use the event parser or not
- `--mouse` chooses whether to enable spammy mouse events or not
