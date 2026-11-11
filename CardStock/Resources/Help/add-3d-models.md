---
title: Add a 3D model
category: Images
summary: Show a 3D model in a page that visitors can turn, zoom and place in their room.
order: 3
---

A 3D model in a page shows in a viewer that visitors can drag to turn, and pinch or scroll to zoom. It spins slowly until someone touches it. On phones and tablets, a button lets them see it in their own room with the camera (augmented reality).

## Add one

1. Open the page and click where the model should go.
2. Click the cube button in the formatting bar.
3. Pick a model from your Files, or click **Choose from Mac…** to copy one in.
4. Set how it shows, then click **Insert**.

This adds a line like `<!-- model /media/files/chair.glb "A walnut chair" -->`.

## Size and background

The settings window has:

- **Description**: what the model is, for people who can't see it.
- **Width**: how much of the page's text width it takes, from 10% to 100%. Narrower models are centered. Phones always show them at full width.
- **Height**: **Auto** keeps a 4:3 shape at any width. **Set** gives it a height in pixels, from 100 to 1200.
- **Background**: **Card color** (Surface, from [Colors](cardstock:colors)), **Transparent** so the page shows through, or a **Color** you pick.
- **Spin**: turns the model slowly until someone touches it.

To change a model later, click anywhere on its line in the page and click the cube button again. The window opens with its current settings, and **Update** changes the line.

The settings are written into the line, so you can also type them: `<!-- model /media/files/chair.glb "A walnut chair" width=60% height=400 background=transparent spin=off -->`. A background can also be a color like `background=#f4efe6`.

You can also copy a model's line from the [Files](cardstock:files) page with **Copy Markdown**, then paste it into a page. On the Files page, choose **3D Models** in the Show menu to see just your models.

## Which file to use

Use **GLB** (`.glb`), the standard for 3D on the web. It holds the model, its colors and textures, and any animation in one file. Most 3D apps can export it. In Blender, choose File › Export › glTF 2.0, then **glTF Binary (.glb)**. CardStock also takes `.gltf` files, but a `.gltf` usually needs other files next to it, so `.glb` is easier.

iPhone and iPad make the version they need for their room view from the GLB, so you only need the one file.

## Keep it small

Big models make pages slow to open, especially on phones.

- Aim for under 5–10 MB. Cloudflare Pages won't publish a single file over 25 MB.
- Shrink textures to 1024 or 2048 pixels.
- Use fewer polygons where you can.

> Models made with Draco compression, a Blender export option, load their decoder from Google's servers. Leave Draco off if you don't want your pages to use another company's server.

## About the viewer

The viewer is Google's free, open-source `<model-viewer>`. CardStock comes with it and adds it to your site the first time a page shows a model, at `/assets/cardstock/model-viewer.min.js`. Your pages load it from your own site, not from anyone else's server.
