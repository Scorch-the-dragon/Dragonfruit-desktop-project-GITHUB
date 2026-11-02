Window-top movement (Windows)
=============================

The pet can land on exposed window tops while falling, walk along them, and
follow a window when you move it. Closing, minimizing, covering, or moving the
window too close to the top of the monitor makes the pet fall again. Walking
past a platform edge also starts a fall.

Shenanigans > Hop onto a window flies to an eligible window. It is also in the
random event pool and can be disabled with its checkbox in Options. If there
is no eligible window, the manual button explains why it cannot run.

WindowPlatforms.gd contains the movement and clearance checks. hop_seconds
sets flight duration; hop_height sets arc height. Partial clipping at the top
of the screen is allowed. minimum_visible_pixels (default 24) keeps a strip of
the pet's actual artwork visible, accounting for transparent sprite margins.
Completely off-screen perches are rejected, including during a moving target's hop.
The existing speed in Main.gd controls walking on windows too.

WindowProbe.gd embeds a read-only PowerShell/Windows helper. It checks window
bounds every 250 milliseconds without reading titles or contents, changing
focus, or moving other apps. Its temporary files live in Godot's user data
folder and are cleaned up when the pet closes. The helper stops when the pet
process exits. Embedding it in GDScript includes it in exported games.

Minimized and cloaked windows, the desktop/taskbar, and this pet application's
own windows are excluded. Covered top segments are subtracted in stacking
order. Transparent/irregular windows are treated as rectangular bounds.
Window detection requires Windows PowerShell; other operating systems and
headless tests retain ordinary screen-edge movement. If local policy blocks
the helper, ordinary pet movement continues without window platforms.
