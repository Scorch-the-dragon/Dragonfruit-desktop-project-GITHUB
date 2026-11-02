# Consumption sounds

Minecraft: Java Edition eating and drinking effects, downloaded from Mojang's
official resource server using the 1.21.1 asset index. These are Minecraft assets,
not original artwork or audio created for this project.

| File | Original asset | Source |
| --- | --- | --- |
| eat1.ogg | minecraft/sounds/random/eat1.ogg | https://resources.download.minecraft.net/df/dfee39084c771182f6b9e7cfb8c8bc4e255747bc |
| eat2.ogg | minecraft/sounds/random/eat2.ogg | https://resources.download.minecraft.net/d2/d26bde554d88f0ca156baf471c44ce2c0e68176c |
| eat3.ogg | minecraft/sounds/random/eat3.ogg | https://resources.download.minecraft.net/9f/9f2c4bab5ed55f1714fffa223985c81babc8f6c0 |
| drink.ogg | minecraft/sounds/random/drink.ogg | https://resources.download.minecraft.net/85/857b75738992d25e338dee640ab191323bcbf798 |

Change `consumption_volume_db` in `Code/Main.gd` to adjust volume. Eating randomly
selects a bite from the three clips; drinking uses the sip clip. Clips repeat
until the consumption timer ends. Leave Loop disabled in Godot's import settings
so the audio player's finished signal can select the next clip.
