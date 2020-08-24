# jsonexplorer

```bash
zig targets | zig build run
```

also contains some things for debugging terminal escape codes:

```
zig build escape && zig-cache/bin/escape_sequence_debug --event --mouse
```

- `--event` chooses whether to use the event parser or not
- `--mouse` chooses whether to enable spammy mouse events or not