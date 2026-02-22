// disable-mouse.js — Strip mouse tracking escape sequences from stdout
// Prevents TUI apps (Ink/React) from capturing mouse wheel events,
// allowing native terminal scrollback in multiplexers like zmx.
//
// Usage: NODE_OPTIONS="--require=$HOME/.local/lib/disable-mouse.js"
//
// Filtered sequences (enable only — leave disable sequences intact):
//   \x1b[?1000h  Basic mouse tracking
//   \x1b[?1002h  Button-event tracking
//   \x1b[?1003h  Any-event (all motion) tracking
//   \x1b[?1006h  SGR extended mouse format

'use strict';

const MOUSE_ENABLE_RE = /\x1b\[\?100[0236]h/g;

const origWrite = process.stdout.write;

process.stdout.write = function (chunk, encoding, callback) {
  if (typeof chunk === 'string') {
    chunk = chunk.replace(MOUSE_ENABLE_RE, '');
  } else if (Buffer.isBuffer(chunk)) {
    const str = chunk.toString('binary');
    const filtered = str.replace(MOUSE_ENABLE_RE, '');
    if (filtered !== str) {
      chunk = Buffer.from(filtered, 'binary');
    }
  }
  return origWrite.call(this, chunk, encoding, callback);
};
