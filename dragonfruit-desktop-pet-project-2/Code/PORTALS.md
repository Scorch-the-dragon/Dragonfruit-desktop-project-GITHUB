Portal props
============

Spawn a blue and an orange portal ball from Spawn menu. Pick up and release
each ball toward a desktop edge. Its first edge hit places a glowing portal
and consumes the ball. A newly spawned ball waits for pickup/release before
placing a portal. Each color has one portal; another hit replaces that color.

Both portals must exist for travel. Walking/climbing pets emerge attached to
the exit edge. Airborne pets emerge moving inward, with the incoming speed
rotated for the exit edge. Screen-impact audio and the landing splat are
skipped on successful travel. A brief cooldown protects airborne exits.
Walkers must leave the exit opening before entering it again, so slow walking
does not create a back-and-forth teleport loop. Turning back after leaving
still allows another trip.

Portal placement uses the released ball's monitor, allowing the pair to span
monitors. Remove all props also removes the portals. Portals do not intercept
mouse clicks. Event-controlled movement is separate from normal traversal.

Adjust portal_length in PetPortals.gd to change the opening size. Glow colors
are drawn procedurally in PortalGlow.gd; ball colors are in PortalBall.gd.
