---
title: When something goes wrong
category: Common Questions
summary: Fixes for publishing and preview problems.
order: 2
---

### See what happened: the Activity Log

[Status](cardstock:status) has an **Activity Log** that lists everything that happens in CardStock:
- your edits to pages, files, settings and styles
- building and publishing
- updates from other Macs
- your website host's build after each publish
- every error

Filter it to **Edits**, **Publishing** or **Problems**, search it, or turn on **All Sites** to see every site's entries. The buttons at its top right export what's shown as a text file (handy when asking for help) and delete entries.

### I published, but my website didn't change

After CardStock publishes to GitHub, your host (such as Cloudflare) builds the website, which usually takes under a minute. CardStock checks how that build went and lists it in the [Activity Log](cardstock:status). If the build failed, you'll also see a message. Click **View Build** next to the entry to see the host's log. A failed build is often a short outage at the host: publish again, or click **Retry build** on the host's page.

### "Some theme files are out of date"

Your site was made with an older version of CardStock, so some newer features don't show. Open [Configuration](cardstock:configuration), pick any page below Site Details, and click **Update Theme Files**. The old files go to your Mac's Trash in case you changed them.

### Publishing says my token doesn't work

Tokens can expire. [Make a new one](help:connect-github) on GitHub, then open **CardStock → Settings… → GitHub**, click **Add Account…** and paste it. Signing in again as the same account replaces the old token.

If the site publishes with the wrong account, pick the right one under **Publishing as** on the [Publishing](cardstock:publishing) page.

### Publishing stopped because of a conflict

The same post was changed on two Macs. CardStock didn't change anything. The purple banner on the [Publishing](cardstock:publishing) page lists the posts both Macs changed. Click **Use GitHub's Version…**: your edits here go to the Trash as a copy named "(edits from this Mac)". Then get the latest and redo your edits.

### "Command Line Tools" are needed

Publishing uses git, which comes with Apple's Command Line Tools. Click **Install Command Line Tools** on the Publishing page, wait for the installer to finish, then click **Check Again**.

### The preview is blank or out of date

Choose **Site → Reload from Disk** (⇧⌘R). If you edited files in another app, this also picks up those changes.

### Still stuck?

Report the problem on [CardStock's GitHub page](https://github.com/wesvasher/CardStock/issues).
