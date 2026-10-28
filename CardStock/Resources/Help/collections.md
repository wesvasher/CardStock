---
title: Collections
category: Writing
summary: Blog, shop, portfolio, videos and your own: a main page that lists items, with categories.
order: 2
---

A **collection** is a section of your site made of three kinds of pages:

- A **main page** that lists everything in it, like `/blog/` or `/work/`, under your own title and text.
- An **item** page for each thing in it: a post, a product, a project, a video.
- **Categories** (if you want them) that list some of the items, like *Travel* in a blog.

Every site starts with a **Blog**. Set up collections in [Collections](cardstock:collections) in Configuration.

## Add a collection

1. In [Collections](cardstock:collections), click **Add Collection…**.
2. Pick a starting point. Each sets sensible choices you can change later:

| Starting point | Good for | Lists items as |
|---|---|---|
| Blog | Dated posts, newest first, on Home and in the RSS feed | A list |
| Shop | Products with a price and a Buy button | Cards |
| Portfolio | Projects or artwork | A gallery of images |
| Videos | Pages built around a YouTube, Vimeo or video file | Cards with thumbnails |
| Custom | Anything else: recipes, events, episodes, case studies | Cards |

3. Name it, and name one item and more than one (like *Recipe* and *Recipes*). These show in CardStock and on your site, like "All recipes".
4. Check the **Address**. The main page lives there, like `/recipes/`, and every page in the collection under it, like `/recipes/pages/lemon-cake/`. It can't change later.
5. Click **Create**. CardStock makes the main page; edit its title and text with **Edit Main Page**.

### Turn a page into a collection

Already have a page you'd like to list things on, like a Recipes page? Open it in [Pages](cardstock:pages), choose **New Collection…** from its **Type** menu, and follow the steps above. That page becomes the collection's main page, keeping its title and text. It moves to the collection's address (like `/recipes/`): links to it in your pages, top bar and footer are updated, and visitors who use the old address are sent to the new one.

To add an item, click **New Page…** in [Pages](cardstock:pages) and choose the item type, like **Recipe**, or click **New Recipe…** in the collection's settings.

## Fine-tune a collection

Choose a collection from the **Collection** menu (sorted by name; the first one shows when you open the page) to see its settings. The preview shows its main page as you change them.

- **Main Page and Categories**: show items as a **List**, **Cards** or a **Gallery**, how many columns, in what order (newest, oldest or by title), and whether to show images, dates, summaries and links to each category. **When empty** is the text shown before there's anything to list.
- **Item Pages**: whether items have a date and show it, the cover image, tags and categories, a **Price and Buy button**, a **Video** player, links to the previous and next item, and the layout new items start with. Turning a field on adds it to each item's editor.
- **Categories**: turn categories on, see each one with how many items it has, and make new ones.
- **Elsewhere**: list the items on the Home page, include them in the RSS feed, and let search find them.



## Delete a collection

Click the red **Delete Collection…** button at the very bottom of its settings, then confirm. Its pages aren't deleted: they become static pages. The main page keeps its address; items and categories move to `/pages/` with the other static pages (like `/pages/lemon-cake/`), so update any links to them.

## Link to a collection

Add its main page to the menu in [Top Navigation Bar](cardstock:top-bar): the page menu next to a link lists every collection. A menu link to a collection stays highlighted on its items' pages too.

## Page addresses

CardStock gives every page its address; there's nothing to set.

| Page | Address |
|---|---|
| Home | `/` |
| A collection's main page | `/blog/`, `/shop/`, `/gallery/`, … |
| A page in a collection (an item or a category) | `/blog/pages/my-trip/`, `/shop/pages/blue-mug/` |
| Any other page | `/pages/about/` |

The last part is made from the page's title when you create it. For a shorter address, like `/subscribe/`, make a [folder](help:folders). Sites made before CardStock 0.6 move to these addresses the first time they open: links in your pages, top bar and footer are updated, and the old addresses redirect to the new ones (in `static/_redirects`).
