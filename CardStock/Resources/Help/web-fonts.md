---
title: Add a web font
category: Theming
summary: Use fonts from Google Fonts and other services.
order: 3
---

1. Find a font on [Google Fonts](https://fonts.google.com), and copy its embed link. It starts with `https://fonts.googleapis.com/css2?family=`. Copying the whole `<link …>` tag is fine too.
2. In [Fonts](cardstock:fonts) in Configuration, next to **Web fonts**, click **Add…**.
3. Paste the link and click **Add Font**.
4. CardStock tells you the font's name. Choose it from the **Body text** or **Headings** menu.

Adobe Fonts and Bunny Fonts links work too, as do direct links to `.woff2`, `.woff`, `.ttf` or `.otf` files.

Web fonts are saved with the site (in `theme/fonts.json`), so they come along when you open the site on another Mac.

To remove one, click **−** next to it in the Web fonts list. Anything using it switches back to the default font.
