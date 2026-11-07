# Photographic direction for STUDIO

This is a practical visual vocabulary for reference-guided portraits and generated stills. The YAML beside this document is the prompt source used by the reference-generation route. The goal is photographic credibility, not a generic “cinematic” filter.

## The camera comes before the grade

Build the image in this order: point of view and camera distance; focal length and framing; motivated key; negative fill and bounce; background separation; exposure; then color and texture. A wide lens does not, by itself, cause facial perspective distortion. Camera-to-subject distance does. The American Cinematographer's lens-distortion explainer demonstrates that perspective changes with camera position, not a magical property of focal length. For a selfie, keep the camera at a believable arm's length and avoid pushing the face inches from an ultra-wide lens.

A useful portrait kit is 35–40 mm equivalent for environmental and handheld work, 50–65 mm for natural portrait coverage, and 85 mm for a tighter portrait from farther away. Treat these as framing choices, not rigid rules. Keep the eye plane in focus; let focus fall away naturally.

## Light with purpose

Stephen H. Burum, ASC, describes three enduring jobs for light: modelling, separation and filling shadows. Start by shaping the set and background, establish the key that sets exposure, then add only the fill needed to preserve the intended shadow detail. Negative fill is not “underexposure”; it removes unwanted bounce so the face retains shape. A white bounce is useful when shadow detail must be lifted without creating an obvious second shadow. Burum's lighting workshop demonstrates how dramatically fill changes mood, including 8:1 and 3:1 examples, while warning against flooding the walls.

For faces, protect natural skin texture and keep a real tonal reference somewhere in the scene. Do not make every face uniformly bright. Night should still read as night; the practical source should motivate the key, and the shadows should retain intentional depth.

## Color management before color styling

A color grade is not a stack of LUTs. Record or receive the source color space, transform it into a known working space, make the creative grade, then apply the correct display/output transform. ARRI's LogC documentation explains that log encodings are scene-based and must be transformed for Rec.709, Rec.2020 or P3 display. The Academy Color Encoding System is a device-independent interchange and color-management system spanning capture, editorial, VFX, mastering and archive.

Use a managed ACES or OCIO pipeline when working with scene-linear or log material. Keep input transforms, creative looks and output transforms separate. Protect hue and saturation in skin; shape contrast with a controlled toe and shoulder; do not clip individual RGB channels just to make a look punchier. For generated JPEG/WebP outputs, treat the files as display-referred unless their metadata proves otherwise. Do not apply a LogC, S-Log or ACES camera-input transform to an ordinary finished JPEG.

## Film is a photochemical response, not an overlay

Use stock references to guide contrast, palette and texture:
- **VISION3 50D / 250D:** daylight-negative character, fine grain, natural skin and generous highlight handling. Kodak's March 2026 VISION3 250D technical sheet documents reduced shadow grain and extended highlight latitude.
- **VISION3 500T:** tungsten-balanced, useful for low-light interiors and mixed practical lighting. Kodak documents reduced shadow grain and extended highlight latitude on the 500T product page.
- **Double-X 5222:** a monochrome motion-picture negative reference for structured grain and strong tonal separation.

Do not add grain as a uniform layer of random pixels. Grain should scale with output resolution and photographic density. Halation belongs around intense bright sources, not around every edge. Light leaks, scratches, frame weave and gate weave are optional artefacts of specific capture/handling processes, not default proof of “authenticity”. Gate weave belongs to moving-film projection, not a still selfie.

## Analog still photography is its own language

Do not transfer motion-picture stock names onto every still-photo look. Still-photo emulsions, formats and lab scans have their own contrast, color and grain signatures:

- **Portra 400** is a high-speed color-negative portrait/fashion reference. Kodak describes natural skin-tone reproduction and use across varied lighting. It is a useful starting point for restrained portraits and candid people photography, not a synonym for beige skin or washed-out blacks.
- **Ektar 100** is a low-speed, fine-grain and highly saturated color-negative reference. Kodak positions it for outdoor, travel, fashion and product work. Use its color separation for landscapes and vivid environments; keep skin hue under control rather than pushing saturation everywhere.
- **Tri-X 400** is a classic panchromatic black-and-white reference with visible grain structure, sharpness and exposure latitude. Kodak lists pushability up to EI 1600. Pushing is a development decision that changes contrast and grain; it is not just a post-production noise slider.
- **VISION3 50D / 250D / 500T** are motion-picture negative stocks, not C-41 still-photo films. Their emulsion response and ECN-2 workflow should not be confused with a Portra or Ektar scan.

For a real analogue capture, record the film stock, format, camera/lens, exposure index, filter, developer/process, lab and scanner profile. A scan is part of the final look: inversion, orange-mask handling, white balance, contrast and scanner light source can materially change the rendering. When generating digitally, ask for the stock's broad tonal/color behaviour and scan character; do not add fake sprocket holes, dust, scratches or random light leaks unless they are a deliberate brief.

## Diffusion and lens character

Tiffen's filter guide distinguishes black halation, white halation, resolution diffusion and contrast reduction. Black Pro-Mist introduces highlight halation while retaining more shadow contrast than conventional Pro-Mist; Black Diffusion/FX softens fine detail while controlling highlight spread. Treat filtration as a measured lens choice: a light touch can reduce brittle digital crispness while keeping eyes sharp. Heavy diffusion quickly becomes a style effect and can erase real skin detail.

Flare needs a source and a lens angle. Anamorphic streaks, veiling flare, chromatic aberration, vignetting and edge softness are optical behaviours, not decorative stickers. Add them only when the camera, lens and light source justify them.

## VFX and compositing

Photoreal compositing depends on matching the camera, perspective, lens, focus, motion blur, illumination, reflections, contact shadows, atmospheric depth and grain. A subject that has perfect segmentation but the wrong light direction still looks pasted in.

For a real VFX pipeline, keep high-dynamic-range scene data in an appropriate linear working space and maintain correct alpha handling. OpenEXR documents scene-linear values and premultiplied alpha as the standard “over” compositing convention. Do not composite display-referred JPEG layers as though they were linear light. Keep plate, CG and grade transforms explicit and preserve metadata; never guess a source color space.

For still portrait generation, the safest VFX choice is often no visible VFX. Use a subtle, coherent depth of field and real atmospheric perspective before adding fog, flares or fake bokeh. A believable background and matching shadow sell the shot better than a pile of effects.

## Reusable shot recipes

| Look | Camera and light | Color and finish |
|---|---|---|
| Natural selfie | 26–30 mm phone main camera, realistic arm's length, open-sky or window key | neutral skin, fine sensor texture, natural framing |
| Window portrait | 50 mm, large side window, negative fill and restrained bounce | quiet highlights, rich but readable shadows |
| Nordic overcast | 40 mm, broad sky key and subtle negative fill | cool-neutral ambience, warm accurate skin |
| Golden hour | 35 mm, low back/three-quarter sun and sky fill | warm highlights, cooler shadows, restrained halation |
| Night practicals | 40 mm fast lens, practical key and limited ambient fill | tungsten-negative character, preserve night |
| Studio editorial | 85 mm, large soft key, negative fill and controlled rim | neutral skin, precise detail, no plastic retouch |
| Daylight negative | 50 mm, controlled key and bounce | VISION3 250D-inspired palette and fine grain |
| Tungsten negative | 40 mm, motivated warm practicals and cooler ambience | VISION3 500T-inspired low-light rendering |
| Monochrome | 50 mm, directional key and rich shadow design | Double-X-inspired tonal texture |
| Soft diffusion | 65 mm, directional soft key and crisp eye focus | subtle black diffusion, restrained halation |

## Sources

- American Society of Cinematographers, [Lighting a Set with Stephen H. Burum, ASC](https://theasc.com/articles/lighting-a-set/), 1 October 2019.
- American Society of Cinematographers, [Understanding Lens Distortion](https://theasc.com/articles/understanding-lens-distortion/).
- SMPTE, [ACES Standards](https://www.smpte.org/standards/aces-standards).
- ARRI, [Log C](https://www.arri.com/en/learn/camera-systems/image-science/log-c) and [REVEAL Color Science](https://www.arri.com/en/learn/camera-systems/image-science/reveal-color-science).
- Adobe, [OpenColorIO and ACES color management](https://helpx.adobe.com/after-effects/desktop/adjust-colors/opencolorio-and-aces-color-management/opencolorio-aces-color-management.html), updated 18 September 2026.
- Eastman Kodak, [VISION3 250D technical information, March 2026](https://www.kodak.com/content/products-brochures/motion-picture/KODAK-VISION3-250D-5207-7207-technical-information.pdf), [VISION3 50D](https://www.kodak.com/en/motion/product/camera-films/50d-5203-7203/features/), and [VISION3 500T](https://www.kodak.com/en/motion/product/camera-films/500t-5219-7219).
- Kodak Alaris, [Portra 400](https://www.kodakprofessional.com/photographers/film/color/kodak-professional-portra-400-film/516), [Ektar 100](https://www.kodakprofessional.com/photographers/film/color/kodak-professional-ektar-100-film/530), and [Tri-X 400](https://www.kodakprofessional.com/photographers/film/black-white/kodak-professional-tri-x-films/515).
- Kodak, [Eastman Double-X 5222/7222](https://www.kodak.com/en/motion/product/camera-films/eastman-double-x-black-white-5222-7222/).
- The Tiffen Company, [Diffusion Guide](https://tiffen.com/pages/diffusion-guide).
- Academy Software Foundation, [OpenEXR technical introduction](https://openexr.com/en/latest/TechnicalIntroduction.html).

Research checked 7 November 2026. Manufacturer descriptions explain technical behaviour and intended applications; they are not universal aesthetic rules. The look profiles are creative starting points and require human review.
