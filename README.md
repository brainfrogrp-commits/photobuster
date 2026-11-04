# Photo Swipe Cleaner

A personal iPhone app that clears out your photo library one random photo at a time.

| Action | What happens |
|---|---|
| Swipe left | Keep the photo. It's saved as accepted and never shown again. |
| Swipe right | Add the photo to the deletion queue. Nothing is deleted yet. |
| Undo | Reverse the last swipe and bring that photo back. |
| Review & Delete | See the queue, tap any photo to keep it instead, then delete the rest in one batch. iOS asks you to confirm, and the photos go to **Recently Deleted**. |

Built with SwiftUI and PhotoKit, no third-party code. Needs iOS 17 or later and Xcode 16 or later.

## Files

```
PhotoSwipeCleaner.xcodeproj    the Xcode project (open this)
PhotoSwipeCleaner/
  PhotoSwipeCleanerApp.swift   app entry point
  ContentView.swift            photo-access screens (ask, denied, limited)
  SwipeScreen.swift            main screen: swipe card, counters, Undo, finished state
  ReviewView.swift             deletion queue and batch delete
  LibraryModel.swift           random picking, undo, deleting, library loading
  DecisionStore.swift          saves accepted and queued photos on the device
  PhotoLoader.swift            loads images, including from iCloud
  Assets.xcassets              app icon
```

---

## 1. Get the project onto your Mac

1. Install **Xcode** from the Mac App Store (it's free). Open it once and let it install any extra components it asks for.
2. Get this folder onto your Mac. On GitHub, open the repository, click the green **Code** button, then **Download ZIP**, and unzip it. (Or, if you use git: `git clone` the repository.)
3. Double-click **`PhotoSwipeCleaner.xcodeproj`**. Xcode opens the project.

## 2. Sign the app with your free Apple ID

1. In Xcode, open the **Xcode** menu, then **Settings…**, then **Accounts**. Click **+**, choose **Apple ID**, and sign in.
2. Close Settings. In the left sidebar, click the blue **PhotoSwipeCleaner** project icon at the top.
3. Under **TARGETS**, select **PhotoSwipeCleaner**, then open the **Signing & Capabilities** tab.
4. Make sure **Automatically manage signing** is ticked.
5. In **Team**, pick your name, which will show **(Personal Team)**.
6. Check **Bundle Identifier**. It is `com.brainfrog.PhotoSwipeCleaner`.
   - If Xcode shows a red error saying the ID isn't available, change it **once** to something unique (for example `com.yourname.PhotoSwipeCleaner`).
   - **After that, never change it again.** Your saved progress is tied to this ID. As long as it stays the same, reinstalling keeps everything.

## 3. Turn on Developer Mode on your iPhone

1. Plug your iPhone into the Mac with a cable. If the phone asks **Trust This Computer?**, tap **Trust** and enter your passcode.
2. On the iPhone, open **Settings → Privacy & Security**, scroll to the bottom, and tap **Developer Mode**.
   - If you don't see it, do step 4 below once first (Xcode trying to install makes the option appear), then come back.
3. Turn it on. The phone restarts. After it restarts, tap **Turn On** and enter your passcode.

## 4. Install and run the app

1. At the top of the Xcode window, click the device menu (next to the app name) and choose **your iPhone**.
2. Press the **▶ Run** button (or **⌘R**). The first build takes a minute.
3. The first time, Xcode may say the app couldn't launch because the developer isn't trusted. That's expected. Do step 5.

## 5. Trust yourself as the developer on the iPhone

1. On the iPhone, open **Settings → General → VPN & Device Management**.
2. Under **Developer App**, tap your Apple ID email, then tap **Trust**, then **Trust** again.
3. Open **Photo Cleaner** from the home screen, or press ▶ Run in Xcode again.
4. When asked about photos, choose **Allow Full Access**.

## Every 7 days: reinstall

Apps signed with a free Apple ID stop opening after 7 days. When that happens, plug in the phone, open the project in Xcode, and press **▶ Run**. That installs it over the old copy, and your accepted photos, queue, and progress are kept. **Don't delete the app from the phone first**, because deleting it erases the saved progress.

---

## Test plan (try this before using your real library)

You'll test with a few throwaway photos. Because the app picks photos at random from your **whole** library, the safest way is **Limited Access**, which lets the app see only the photos you choose.

**Setup**

1. Take **6 junk photos** with the Camera, for example of a wall. Number them by holding up 1–6 fingers so you can tell them apart.
2. Open **Settings → Photo Cleaner → Photos** and choose **Limited Access**. Then tap **Edit Selected Photos** and select only the 6 junk photos.
3. Open Photo Cleaner. You should see the orange **Limited access** notice and **6 left**.

**Tests** (tick each one)

- [ ] **Short swipe:** drag a photo a little to the left and let go. It snaps back and the count stays at 6.
- [ ] **Labels:** drag left and a green **KEEP** label appears. Drag right and a red **DELETE** label appears.
- [ ] **Keep:** swipe a photo all the way **left**. The count drops to 5. Remember which photo it was.
- [ ] **Queue:** swipe a photo all the way **right**. You see **1 queued**, and the photo is still in the Photos app.
- [ ] **Undo a queue:** tap **Undo**. That same photo comes back and the count reads **0 queued**. Swipe it right again.
- [ ] **Undo a keep:** swipe the next photo **left**, tap **Undo**, and check it comes back. Then swipe it left again.
- [ ] **Restart:** swipe up to close the app completely, then reopen it. The counts are the same, and the photos you kept never reappear.
- [ ] **Finish:** swipe the rest so that at least **3 are queued**. You see **All Done** and a prompt to review the queue.
- [ ] **Take one back:** tap **Review & Delete**, then tap one photo. It leaves the queue. Note which one.
- [ ] **Cancel:** tap **Delete N Photos**. When iOS asks, tap **Don't Allow**. Nothing is deleted, and the queue still shows the same photos.
- [ ] **Delete:** tap **Delete N Photos** again and this time tap **Delete**. Open **Photos → Albums → Recently Deleted**. Only the queued photos are there, and the one you took back is not.

When everything passes, delete the junk photos, then go to **Settings → Photo Cleaner → Photos** and choose **Full Access**. Your real library loads, and the junk photos you kept stay marked as reviewed.

**Optional iCloud check:** if you use iCloud Photos with **Optimize iPhone Storage**, some photos show **Downloading from iCloud…** for a moment. With Airplane Mode on, a photo that isn't on the phone is skipped and counted under **couldn't load**. It isn't marked as reviewed, and **Try Those Again** on the All Done screen brings it back.

---

## How it works

- **Saved state:** accepted and queued photos are stored by their PhotoKit local identifier in `Application Support/decisions.json` on the phone. Each swipe is saved right away. Reinstalling over the app with the same bundle ID keeps this file.
- **Large libraries:** at launch the app lists only photo *identifiers*, not images, in the background. It loads one full-size image at a time and quietly prepares the next, so swiping stays quick even with tens of thousands of photos.
- **Videos** are left out. Hidden photos are left out too.
- **Deleting:** nothing is deleted on swipe. Review & Delete makes one standard PhotoKit delete request, so iOS shows its own confirmation and the photos go to Recently Deleted for about 30 days. The queue is cleared only after the delete succeeds.
- **Taking a photo out of the queue** in Review counts as keeping it.
- **Photos deleted elsewhere** (for example in the Photos app) are dropped from the queue automatically.
- **Undo** works for swipes made since the app last opened, and since your last Review edit or batch delete.
