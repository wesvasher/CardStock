---
title: Manage your files
category: Images
summary: See every image and file, organize them in folders, reuse them, and delete ones you don't need.
order: 2
---

Open [Files](cardstock:files) in the sidebar. It lists everything in your site's `media` folder: images you've added to pages, files added on the Files page, and anything you copy into the folder in Finder. The list updates by itself when the folder changes.

## Add files

- Click **Add Files…**, or
- Drag files from Finder onto the Files page, or
- Copy files into the site's `media` folder in Finder.

Files added on the Files page go into the selected folder (or the folder of the selected file), shown next to the buttons at the bottom. Images added in the editor go into a folder for their page.

## Organize files in folders

The Files page lists everything in one list, like Finder's list view. Folders come first, then files. Click the triangle next to a folder to show what's inside, and click it again to hide it. Folders inside folders open the same way.

- **Open or close a folder**: click its triangle, or double-click the folder.
- **Make a folder**: click **New Folder…** at the bottom. It goes inside the selected folder, so you can make folders inside folders. Or right-click a folder and choose **New Folder Inside…**.
- **Move files**: drag them onto a folder. Hold them over a closed folder for a moment and it opens, so you can drop them into a folder inside it. Drop them in the empty space below the list to move them back to the top. Or right-click them and choose **Move To**. Select several first to move them together.
- **Rename, move or delete a folder**: right-click it. **Move to Trash…** puts the folder and everything in it in your Mac's Trash.
- **Find a file anywhere**: searching or filtering looks in every folder, and each file shows which folder it's in.

Folder names become part of your files' web addresses (`/media/photos/2026/beach.jpg`), so they use lowercase letters, numbers and dashes: "Product Photos" becomes `product-photos`.

When a file or folder moves or is renamed, CardStock updates every link to it in your pages, site settings and theme, and its tags go with it, so nothing on your site breaks. An optimized image's smaller version moves with it. Publish to update your live site. Folders you make or change in Finder show up here too, but links aren't updated for moves made in Finder.

## Use a file in a page

1. Click **Copy Markdown** on the file.
2. Open the page or post and click where it should go.
3. Paste (⌘V).

Images are added as pictures, and other files such as PDFs as a download link. An optimized image comes with both sizes, so it opens full-screen when clicked.

## Edit an image

Select an image and use the toolbar above its preview:

- **Rotate** left or right, and **flip** horizontally or vertically
- **Crop** to Square, 4:3, 3:2 or 16:9 (centered)
- **Auto Enhance**: Apple's one-tap fix for exposure, color and contrast
- **Filters**: Apple's photo effects, such as Mono, Noir and Chrome
- **Remove Background**: keeps the subject on a transparent background, saved as a new PNG next to the original
- **Undo**: steps back through your changes

Edits change the image everywhere it's used, including its smaller version on the page. Publish to update your live site.

## Which files are used?

Each file says which pages use it. Files nothing uses say **Not used on any page** in orange; choose **Not Used** at the top to see just those.

> Files that aren't used are still published with your site.

## Delete a file

1. Click **⋯** on the file (or right-click it) and choose **Move to Trash…**.
2. Confirm. The file goes to your Mac's Trash.
3. Publish. The file is removed from GitHub and your live site too.

If a page still uses the file, CardStock warns you first, because that page will show it as missing. Removing an image from a page's text doesn't delete the file; delete it here when you're sure.

Changed your mind? Put it back from your Mac's Trash with **Put Back**, before you empty the Trash.
