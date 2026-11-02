# Images the pet can bring

Put PNG, JPG/JPEG, WebP, or BMP files directly in this folder.
Choose Shenanigans > Bring an image, or let it happen as a random event.
You can disable it in Options > Allowed events.

The folder is rescanned each time, so you can add images while the pet is running.
The pet randomly chooses a file and runs off the left or right edge to retrieve it.
The delivered window keeps the whole image visible without stretching it. Resize,
move, or close it normally. Every delivery opens a new window; earlier images stay open
until you close them.

Original files are never modified. Unreadable files and files over 32 MiB are skipped.
Very large images are scaled down to a maximum of 4096 pixels per side in memory.
If no suitable image exists, the pet brings an explanation of where to add images.

For an exported game, copy this PetImages folder beside the executable so people
can add their own images. The supplied hello.png is a copy of the pet's sitting sprite.
