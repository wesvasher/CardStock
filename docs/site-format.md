# CardStock site format

A CardStock site is a folder (and a GitHub repo) of Markdown files plus a small HTML theme. CardStock turns it into a finished static website in `public/` and commits that too, so the host only has to serve files. There is no build step on Cloudflare.

## Folder layout

```
my-site/
├── site.json          Site settings
├── My Site.cardstock  Project file: double-click to open the site in CardStock
├── pages/             Every page, one Markdown file each; `type:` says what it is. index.md is the Home page
├── media/             Images and other files, served at /media/
├── static/            Copied as-is to the site root (favicon.ico, robots.txt, _redirects)
├── theme/
│   ├── theme.json     Configuration choices (fonts, colors, corners, width). Optional
│   ├── fonts.json     Web fonts added to the site. Optional
│   ├── base.html      Page shell shared by every page
│   ├── home.html      Home page (list of recent posts)
│   ├── post.html      A blog post
│   ├── page.html      A static page (also used for Home's 404 page)
│   ├── blog-category.html   A blog category and its posts
│   ├── product.html         A product
│   ├── shop-category.html   A shop category and its products
│   ├── shop.html            /shop/: every product
│   ├── template.html        The Template page: every part of the style, for CardStock's preview. Not published
│   ├── layouts/             Page layouts a page can choose with `layout:` (wide.html, hero.html, …)
│   └── assets/        CSS, fonts and scripts, served at /assets/
├── public/            Generated website. Don't edit by hand.
└── .cardstock-local/  Per-Mac data, ignored by git (scheduled-publish.json, github-account)
```

## site.json

```json
{
  "title": "My Site",
  "description": "Notes and work.",
  "author": "Your Name",
  "url": "https://my-site.pages.dev",
  "language": "en",
  "nav": [
    { "title": "Blog", "url": "/" },
    { "title": "Shop", "url": "/shop/" },
    { "title": "About", "url": "/about/" }
  ],
  "header": {
    "mode": "shrinking",
    "logo": "/media/files/logo.svg",
    "logoHeight": 56,
    "compactLogo": "/media/files/icon.svg",
    "compactLogoHeight": 28,
    "showTitle": false,
    "showLogo": true,
    "logoWidth": 0,
    "logoAlt": "",
    "logoPosition": "left",
    "logoPadding": { "top": 0, "right": 0, "bottom": 0, "left": 0 },
    "height": 96,
    "compactHeight": 56,
    "showLeftLinks": false,
    "leftLinks": [],
    "showCenterLinks": false,
    "centerLinks": [],
    "showRightLinks": true,
    "mobileMenu": true
  },
  "footer": {
    "enabled": true,
    "showCopyright": true,
    "copyrightName": "",
    "links": [{ "title": "Privacy Policy", "url": "/privacy-policy/" }],
    "showFeed": true,
    "logo": {
      "image": "/media/files/logo.png",
      "alt": "",
      "width": 120,
      "height": 40,
      "placement": "left",
      "paddingTop": 16,
      "paddingBottom": 16
    },
    "menus": [{ "title": "Follow", "page": "social" }],
    "attribution": { "enabled": false, "text": "" }
  }
}
```

`url` is the public address with no trailing slash. It is used for the RSS feed and canonical links.

`footer` is optional; without it the footer is on with a copyright notice and an RSS link. `copyrightName` empty means the author, or the site title when there's no author. The copyright shows as `© <current year> <name>`.

`header` is optional: the top navigation bar, edited in Configuration → Top Navigation Bar. `mode` is `scrolls` (part of the page; the default), `fixed` (stays at the top at `height`, with the page blurred behind it) or `shrinking` (starts at `height` and shrinks to `compactHeight` as the page scrolls, the logo going from `logoHeight` to `compactLogoHeight` and fading into `compactLogo` when there is one). `logo` empty shows the site title; `showTitle` shows the title next to a logo. `showLogo` false hides the logo (and compact logo), keeping the other logo settings; `showTitle` shows the site title, on its own or next to the logo. With both off, no logo or title is shown. `logoWidth` 0 follows the image's shape (SVG logos always do); `logoAlt` empty uses the site title. `logoPosition` (`left`, `center`, `right`) places the logo and title in the bar, with `logoPadding` around them. The bar has three groups of links: `leftLinks`, `centerLinks`, and `nav` on the right, each shown when its `show…Links` is true (`showRightLinks` defaults to true, so sites made before groups keep their menu). `mobileMenu` (default true) folds the links into a menu button on screens up to 600px wide, which opens them in a full-screen overlay (`header.mobileMenu` in templates is true only when it's on and there are links; base.html adds `has-mobile-menu` to `.site-bar`, `has-brand` to the slot holding the logo and title, a `.nav-toggle` button, and a `#nav-overlay` with every shown link after the bar). Top bar links (in `nav`, `leftLinks` and `centerLinks`) may also have `"button": true` (shown as a button, styled by `navButton` in theme.json) and `"icon"`, the id of one of CardStock's bundled icons (Lucide: `search`, `house`, `mail`, `shopping-bag`, `github`, …), output as an inline `<svg class="nav-icon">`; a link with an icon and no `title` shows just the icon, with an `aria-label`. Sizes are pixels.

`footer.attribution` is optional: when `enabled`, the footer links to https://github.com/wesvasher/CardStock in a new window, with `text` (empty means `Designed with CardStock`).

`footer.menus` is optional: drop-down buttons next to the RSS button. `page` is the slug of a link menu page (`pages/social.md` is `social`); `title` is the button text, the page's title when empty. Menus whose page is missing or has no links aren't shown.

`footer.logo` is optional. `image` empty means no logo. `width` and `height` are pixels on the page; 0 leaves that side to the browser. `alt` empty uses the site title. `placement` is `left` (in the footer row, before the copyright) or `below` (its own centered row under the footer, with `paddingTop` and `paddingBottom` in pixels).

## Content files

Each file is Markdown with a short header (front matter) between `---` lines. The file name, without `.md`, is the slug used in the URL, so `posts/hello-world.md` is published at `/posts/hello-world/`. Slugs use lowercase letters, numbers and hyphens.

```markdown
---
type: post
title: Hello, world
date: 2026-10-20
summary: The first post.
tags: [meta, news]
categories: [notes]
cover: /media/hello.jpg
draft: false
---

Post body in **Markdown**.
```

The header is a small subset of YAML: one `key: value` per line. A value is text (quotes optional), `true`/`false`, or a list in `[a, b]` form. Unknown keys are kept as they are and passed to templates.

Every page lives in `pages/`. `type` says what kind of page it is; without it (or with `page`) it's a static page. `pages/index.md` (Home), `pages/404.md` and `pages/template.md` (Template) are always static pages. File names are unique across all types.

| `type`          | Is                                  | Published at       | Template             |
|-----------------|-------------------------------------|--------------------|----------------------|
| (none) / `page` | Static page                         | `/<slug>/`         | `page.html`          |
| `post`          | Blog post                           | `/posts/<slug>/`   | `post.html`          |
| `blog-category` | Blog category, listing its posts    | `/blog/<slug>/`    | `blog-category.html` |
| `product`       | Product                             | `/shop/<slug>/`    | `product.html`       |
| `shop-category` | Shop category, listing its products | `/shop/<slug>/`    | `shop-category.html` |
| `links`         | Link menu for the footer            | not published      | –                    |

| Key          | Used by            | Meaning                                   |
|--------------|--------------------|-------------------------------------------|
| `title`      | all                | Display title                             |
| `type`       | all                | Page type (above)                         |
| `date`       | posts              | `YYYY-MM-DD`. Sets ordering, newest first |
| `summary`    | all                | Short description for lists and meta tags |
| `tags`       | posts              | List of tags                              |
| `categories` | posts, products    | Slugs of the blog or shop category pages it's listed on, e.g. `[travel, notes]` |
| `price`      | products           | Price as shown, e.g. `$24.00`             |
| `buy`        | products           | Checkout link for the Buy button (Stripe Payment Links, Gumroad, Etsy, …) |
| `buyLabel`   | products           | Buy button text; `Buy Now` when empty     |
| `cover`      | all                | Image path, usually `/media/…`            |
| `draft`      | all                | `true` hides it from the published site   |

## Images

Images added in CardStock are stored per item: `media/posts/<slug>/` for blog posts and `media/pages/<slug>/` for every other type (older sites may also have `media/projects/`), with file names made from the original name (`beach-day.jpg`). Optimized images (the default) are saved twice and linked, so the inline version opens the large one:

```markdown
[![Beach day](/media/posts/trip/beach-day-small.jpg)](/media/posts/trip/beach-day.jpg)
```

- Large: at most 2400 px on the long side. Inline (`-small`): 1200 px. JPEG at quality 0.82; PNGs stay PNG. Metadata such as GPS location is not kept.
- Images 1200 px or smaller are saved once, as a plain `![alt](…)`.
- "Full resolution" copies the original (HEIC, TIFF and BMP are converted to full-size JPEG). GIF and SVG are always copied as they are.

Any page with an image linked to an image file (`<a href="….jpg"><img …></a>`) gets CardStock's lightbox: a `<style id="cardstock-lightbox">` in `<head>` and a `<script id="cardstock-lightbox-script">` before `</body>`. It opens the linked image full-screen; arrow keys, buttons or swipes move through every linked image on the page; Escape or clicking outside closes it. It works with any theme.

### Files

Everything in `media/` is listed on CardStock's Files page, which watches the site folder (FSEvents) so files added or removed in Finder appear straight away. An image's `-small` inline version is shown with its full-size file. Each file shows which items use it (any reference to `/media/…` in an item, `site.json`, or theme and static files).

Copy Markdown gives `![Description](/media/…)` for images (wrapped in a link to the full-size file when there's a `-small` version) and `[Description](/media/…)` for other files. Files added on the Files page are copied into `media/files/` with web-safe names. Deleting a file moves it (and its `-small` version) to the Mac's Trash; the next publish commits the removal. CardStock never deletes or moves media files on its own.

## Published URLs

| Source                  | URL                     | Template                     |
|-------------------------|-------------------------|------------------------------|
| `pages/index.md` + posts | `/`                    | `home.html`                  |
| `pages/<slug>.md` (by `type`) | see the type table above | see above            |
| (all products)          | `/shop/`                | `shop.html` (only when there are products) |
| `pages/404.md`          | `/404.html`             | `page.html`                  |
| `pages/template.md`     | not published (`/_template/` in the preview) | `template.html` |
| (all posts)             | `/feed.xml`             | built in (RSS 2.0)           |

Every page is rendered with its own template, and the result is placed inside `base.html` as `body`. Slugs `posts`, `blog`, `shop`, `links`, `media`, `assets` and `template` are reserved. A theme without the newer templates (`blog-category`, `product`, `shop-category`, `shop`) uses CardStock's built-in versions.

`template.html` renders the Template page, `pages/template.md`: sample colors, fonts, text, lists, code, tables, buttons, a post list and product cards, with the page's own text under the title, wrapped in `base.html` with the usual globals. Like Home and 404, the Template page is always a static page and can't be deleted. CardStock shows it at `/_template/` in the preview only; it's never written to `public/`. CardStock adds the page and the template to sites that don't have them when they open, and uses its built-in template if the file is missing.

### Search

`pages/search.md` is the Search page, published at `/search/` and drawn with `theme/search.html` (CardStock's built-in version when missing). It's a fixed page like Home: its title and text show above a search field. Its template gets `search.index` (`/search.json`), `search.placeholder` and `search.buttonLabel`. The page loads the index with a small script and filters it as visitors type; `/search/?q=words` opens with a search done.

`/search.json` is a list of the findable pages, each with `title`, `url`, `type` (`Page`, `Post`, `Product` or `Category`), `date` (posts), `summary`, `tags` (tags plus category names) and `text` (the page's text without formatting, up to about 5,000 characters). Drafts are left out of published sites, as are Home, the 404 page, the Template and Search pages and link menus.

A line holding only `<!-- search -->` (outside code blocks) shows a search box: a `<form class="search-box" action="/search/">` with a `q` field and a button, preceded once per page by a small `<style>` block.

Settings in `site.json`:

```json
"search": {
  "enabled": true,
  "kinds": ["page", "post", "product"],
  "placeholder": "Search",
  "buttonLabel": "Search"
}
```

`enabled: false` leaves out `/search/`, `/search.json` and every search box. `kinds` are page types (`page`, `post`, `product`, `blog-category`, `shop-category`).

### Newsletter box

A line holding only `<!-- newsletter -->` (any case or spacing, not inside a code block) marks where a page shows the newsletter sign-up box. It's set in `site.json`:

```json
"newsletter": {
  "heading": "Subscribe to the newsletter",
  "text": "Get new posts by email. Unsubscribe any time.",
  "embed": "<iframe src=\"https://example.com/embed\"></iframe>",
  "style": "card",
  "alignment": "left"
}
```

`embed` is the newsletter service's embed code, used as is. `style` is `card` (uses the Components card variables) or `plain`; `alignment` is `left` or `center`. The box is a `<section class="newsletter newsletter-<style> newsletter-<alignment>">` with an optional `<h2>` and `<p>`, then `<div class="newsletter-embed">` holding the embed code, preceded once per page by a small `<style>` block. Without embed code, the box is left out of published pages (the preview shows a note). CardStock's preview shows a sample page with the box at `/_newsletter/` (never published).

### Page layouts

A page can choose a layout with `layout: <name>` in its front matter, where `<name>` is a file in `theme/layouts/` without `.html`. The layout replaces the page type's template (inside `base.html`); without `layout`, or when the file is missing, the type's template is used ("Standard"). The built-in layouts are `wide`, `hero`, `sidebar`, `two-columns` and `landing`. CardStock copies them into sites without a `theme/layouts` folder when they open, and uses its built-in ones while the folder is missing.

A layout file starts with a comment describing it, which isn't published:

```html
<!--
name: Hero
description: The title over a big cover image, with an intro.
areas: Intro, Text
main: Text
types: page, post
-->
```

`areas` are the places for the page's own text. A line `<!-- section -->` in the Markdown (outside code blocks) is a section break: sections fill the areas in order, extra sections join the last area, and text without breaks goes into the `main` area (the first when not given). `types` limits which page types offer the layout (all when absent).

Layouts get the same values as the type's template, plus:

- `page`: the page's fields for every type (a post's or product's too), with `content` (all the text), `sections` (a list, one HTML string per section), `meta` (HTML above the text: a post's date, categories and tags, or a product's price), `actions` (HTML below it: a product's Buy button and categories) and `listing` (HTML for a category's posts or products, or Home's posts).
- `section`: the HTML for each area by number, `section.1`, `section.2`, …
- `recentPosts` (the five newest) and `blogCategories`.

CardStock previews a sample page in each layout at `/_layouts/<name>/` (`/_layouts/standard/` for Standard). Those addresses are never published.

Sites made before page types kept posts in `posts/` and projects in `projects/`. CardStock moves them into `pages/` when the site is opened: posts get `type: post` (same address); projects become static pages at `/<slug>/`, with `static/_redirects` lines sending `/portfolio/…` to the new addresses (Cloudflare Pages reads this file) and a `/portfolio/` menu link titled Portfolio removed.

`pages/index.md` is the Home page. It's published at `/` using `home.html`, which gets the page's fields and text as `page` (`page.content` is its rendered Markdown) along with the list of `posts`. It's never a draft. Without it, `home.html` renders with just the post list.

A page with `type: links` is a link menu. It isn't published at its own address; its links fill a drop-down menu in the footer (`footer.menus` in site.json). Each `[Title](url)` link becomes a menu item, and a bare `https://` or `mailto:` address becomes one named after its site (YouTube, LinkedIn, GitHub, and so on, otherwise the domain). Everything else in the page is ignored.

## Templates

Templates are plain HTML with a few tags:

| Tag                                   | Does                                            |
|---------------------------------------|-------------------------------------------------|
| `{{ name }}`                          | Inserts a value, HTML-escaped                   |
| `{{{ name }}}`                        | Inserts a value as raw HTML                     |
| `{{#if name}} … {{else}} … {{/if}}`   | Shows a block when the value is present and not empty or `false` |
| `{{#each name}} … {{/each}}`          | Repeats a block for each item in a list         |

Names use dots for nested values (`site.title`, `post.url`). Inside `{{#each}}`, the current item's fields are available directly (`{{ title }}`), and `{{ this }}` is the item itself. Outer names stay available.

### Values

Available everywhere:

- `site.title`, `site.description`, `site.author`, `site.url`, `site.language`
- `nav`: the right-hand links (empty when `showRightLinks` is off): list of `title`, `url`, `current` (true for the section being shown)
- `page.title`: title of the page being rendered
- `page.isHome`: true on the home page
- `page.description`: summary for meta tags
- `page.url`: path of the page being rendered
- `year`: current year
- `header`: `mode`, `fixed` (true for fixed and shrinking bars), `shrinks`, `logo` and `compactLogo` (addresses, empty when unset), `logoAlt`, `logoWidth` (true when a width is set), `showTitle`, `brandLeft`, `brandCenter` or `brandRight` (where the logo and title go; all false when both are off), `brandStyle` (their padding, empty when none), `left`, `center` and `right` (the link groups that are on, each a list like `nav`, whose links also have `button`, `icon` (inline SVG) and `label` (for icon-only links)), and `style` (CSS variables `--bar-h`, `--bar-h-compact`, `--logo-h`, `--logo-h-compact`, plus `--logo-k` (compact logo height ÷ logo height) when they differ and `--logo-w` when a width is set, for the `.site-bar` element; the shrinking script sets `--p` from 0 to 1 as the page scrolls)
- `footer`: `enabled`, `copyright` (the full line, e.g. `© 2026 Ann Lee`, or empty when off), `links` (list of `title`, `url`), `rss` (true to link the feed), `logo` (empty when there's none; otherwise `src`, `alt`, `style` (its width and height as CSS), `left` or `below` (true for the chosen placement), and `rowStyle` (padding for the row below)), `attribution` (empty when off; otherwise `text` and `url`), `menus` (list of `title` and `links`, each link with `title`, `url` and `external`, true for other sites)

In `base.html`: `body` is the rendered page.

An item (any page) has `title`, `slug`, `url`, `type`, `date` (`2026-10-20`), `dateDisplay` (`October 20, 2026`), `summary`, `tags`, `cover`, `content` (rendered HTML), plus any other header keys. Posts and products also have `categoryLinks` (list of `title`, `url` for the published categories they're in). Products also have `price`, `buy` and `buyLabel`.

- `home.html`: `posts`, the list of published posts, and `page` with the Home page's fields and `content`.
- `post.html`: `post`.
- `page.html`: `page` (also carries the item's fields).
- `blog-category.html`: `page` (the category's fields and `content`) and `posts`, its published posts, newest first.
- `product.html`: `product`.
- `shop-category.html`: `page` and `products`, its published products.
- `shop.html`: `products`, every published product.

## Theming

`theme/theme.json` holds the choices made in CardStock's Configuration (Fonts, Colors, Components):

```json
{
  "appearance": "auto",
  "bodyFont": "system-serif",
  "headingFont": "system-sans",
  "fontSize": 18,
  "h1Size": 32,
  "radius": 8,
  "contentWidth": 40,
  "buttonStyle": "outline",
  "buttonRadius": 6,
  "buttonPaddingX": 16,
  "buttonPaddingY": 8,
  "cardRadius": 10,
  "cardPadding": 20,
  "cardBorder": true,
  "cardShadow": "none",
  "coverRadius": 8,
  "imageRadius": 0,
  "codeRadius": 8,
  "quoteColor": "line",
  "quoteBarWidth": 3,
  "tableStripes": false,
  "menuRadius": 8,
  "navFont": "",
  "navSize": 15,
  "navWeight": 400,
  "navLight": { "link": "", "hover": "", "current": "", "pressed": "", "icon": "" },
  "navDark": { "link": "", "hover": "", "current": "", "pressed": "", "icon": "" },
  "navButton": { "light": { "background": "", "text": "", "border": "", "icon": "" }, "dark": { … }, "borderWidth": 0, "radius": 8, "pill": false, "opacity": 100, "blur": 0, "shadow": "none", "iconPosition": "left", "paddingX": 14, "paddingY": 6 },
  "light": { "background": "#fdfcfa", "surface": "#ffffff", "text": "#1d1d1f", "muted": "#6e6e73", "accent": "#b4532a", "line": "#e5e3df" },
  "dark":  { "background": "#161617", "surface": "#1f1f21", "text": "#ececec", "muted": "#9a9aa0", "accent": "#f08a5d", "line": "#2e2e30" }
}
```

`appearance` is `auto` (follows the visitor's device), `light` or `dark`. The component settings are pixels except `buttonStyle` (`outline`, `filled`), `cardShadow` (`none`, `soft`, `strong`), `quoteColor` (`line`, `accent`) and the two true/false values. `navFont`, `navSize` (px) and `navWeight` (400, 600 or 700) style the top bar's links; an empty `navFont` uses the headings font, and a font named there is loaded like the body and heading fonts. `navLight` and `navDark` color the links (`link`), hovered links (`hover`), the current page's link (`current`) and links being clicked (`pressed`) in each appearance, as `#rrggbb`; empty follows the palette (secondary text, text, text, and the hover color). Corner radii missing from older files follow `radius` as the theme did before (buttons ×0.75, cards ×1.25, covers, code blocks and menus ×1). Fonts are built-in stacks (`system-sans`, `system-serif`, `system-rounded`, `system-mono`), Google Fonts from CardStock's list named in lowercase with hyphens (`lora`, `source-serif-4`), or web fonts added by link, written as `custom:<family>`.

Web fonts added by link live in `theme/fonts.json`, so they stay in the site's font menus whatever style is in use:

```json
{
  "fonts": [
    { "family": "Roboto", "url": "https://fonts.googleapis.com/css2?family=Roboto&display=swap", "style": "sans" },
    { "family": "Recoleta", "url": "https://cdn.example.com/Recoleta.woff2", "style": "serif" }
  ]
}
```

A stylesheet `url` is added to pages as a `<link>`. A font file `url` (`.woff2`, `.woff`, `.ttf`, `.otf`) gets an `@font-face` rule. Only fonts in use are loaded. `style` (`sans`, `serif`, `mono`) picks the fallback shown while the font loads.

`theme.json` may also have a `customFonts` list in the same format. Saved styles use it to carry the fonts they need; older sites stored their web fonts there, and CardStock moves them into `fonts.json` when it opens the site.

When the file exists, CardStock adds a `<style id="cardstock-theme">` block (and a Google Fonts `<link>` if needed) at the end of every page's `<head>`. It sets these CSS variables, which a theme's stylesheet should use:

| Variable          | From                 |
|-------------------|----------------------|
| `--font-body`     | `bodyFont`           |
| `--font-heading`  | `headingFont`        |
| `--font-size`     | `fontSize` (px)      |
| `--h1-size`       | `h1Size` (px)        |
| `--radius`        | `radius` (px)        |
| `--measure`       | `contentWidth` (rem) |
| `--bg`            | `background`         |
| `--card`          | `surface`            |
| `--text`          | `text`               |
| `--muted`         | `muted`              |
| `--accent`        | `accent`             |
| `--line`          | `line`               |
| `--nav-link`, `--nav-hover`, `--nav-current`, `--nav-pressed`, `--nav-icon` (`currentColor` when empty) | `navLight` / `navDark` (set with the palette, so they change with appearance) |
| `--navbtn-bg`, `--navbtn-text`, `--navbtn-border`, `--navbtn-icon` (`currentColor` when empty) | `navButton.light` / `.dark` (empty: accent, page background, line) |
| `--navbtn-border-width`, `--navbtn-radius` (999px when `pill`), `--navbtn-alpha` (%), `--navbtn-blur`, `--navbtn-shadow`, `--navbtn-pad-x`, `--navbtn-pad-y` | the rest of `navButton` |
| `--nav-icon-dir` | `navButton.iconPosition` (`row` or `row-reverse`) |
| `--nav-font`, `--nav-size`, `--nav-weight` | `navFont` (a font stack, or `var(--font-heading)`), `navSize` (px), `navWeight` |
| `--button-radius`, `--button-pad-x`, `--button-pad-y` | `buttonRadius`, `buttonPaddingX`, `buttonPaddingY` (px) |
| `--button-bg`, `--button-text` | set only when `buttonStyle` is `filled` (accent background, page-colored text) |
| `--card-radius`, `--card-padding` | `cardRadius`, `cardPadding` (px) |
| `--card-border`, `--card-shadow` | `cardBorder`, `cardShadow` (full `border` and `box-shadow` values) |
| `--cover-radius`, `--image-radius`, `--code-radius`, `--menu-radius` | `coverRadius`, `imageRadius`, `codeRadius`, `menuRadius` (px) |
| `--quote-bar`, `--quote-bar-width` | `quoteColor` (a color), `quoteBarWidth` (px) |
| `--table-stripe`  | `tableStripes` (a background for even rows, or `transparent`) |

Without `theme.json`, nothing is added and the theme's CSS is used as written.

## Project file

Every site has one project file at its root, named after the folder: `<Site Name>.cardstock`. Double-clicking it in Finder opens the site in CardStock. It also holds CardStock's settings for the site, travels with the folder, and is committed with the site. It never holds passwords, tokens or account names. GitHub tokens live in each Mac's Keychain, one per account, and the account a Mac publishes a site with is saved in `.cardstock-local/github-account` (per Mac, so two people can publish the same site from their own accounts).

```json
{
  "format": "cardstock-project",
  "version": 1,
  "github": { "branch": "main", "repo": "owner/my-site" }
}
```

`github` is present only when the site is linked to GitHub. Without it the site is local-only; GitHub is optional. Renaming the file is fine; CardStock uses the first `.cardstock` file it finds in the root. Sites made before project files existed get one the next time CardStock opens them, and an old `cardstock.json` is moved into it.

## Publishing

Publish builds `public/`, commits everything with git, pulls changes pushed from other computers (rebasing local commits on top), rebuilds if anything came in, and pushes. Clashes inside `public/` are resolved automatically because it is regenerated. Clashes in content files stop the publish without changing anything.

## Hosting on Cloudflare Pages

Connect the repo in Cloudflare Pages with:

- **Build command:** none
- **Build output directory:** `public`

Each push from CardStock updates the site.
