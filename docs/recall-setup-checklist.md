# Recall Feature Setup Checklist

## ✅ Completed Automatically

- [x] Removed SoundPrint/RockList code references
- [x] Deleted SoundPrint/RockList files
- [x] Created Recall Swift code (models, service, views)
- [x] Created Supabase schema SQL
- [x] Created Edge Functions
- [x] Added Recall to tab bar
- [x] Created documentation

## 🔧 Manual Steps Required

### 1. Update Xcode Project File

**Option A: Using Xcode (Recommended)**
1. Open `Rockout.xcodeproj` in Xcode
2. In Project Navigator, find and remove (right-click → Delete → Move to Trash):
   - `Rockout/Views/SoundPrint/` folder
   - `Rockout/Views/RockList/` folder
   - `Rockout/Services/RockList/` folder
   - `Rockout/ViewModels/RockList/` folder
   - `Rockout/Models/RockList/` folder
   - `Rockout/Views/Onboarding/Slides/SoundPrintSlide.swift`
   - `Rockout/Views/Onboarding/Slides/RockListsSlide.swift`
   - `RockoutTests/RockListServiceTests.swift`
   - `RockoutTests/RockListViewModelTests.swift`
   - Video files: `soundprint_onboarding.mp4`, `rocklist_onboarding2.mp4`

3. Add new Recall files (right-click folder → Add Files to "Rockout"):
   - `Rockout/Models/Recall/RecallModels.swift`
   - `Rockout/Services/Recall/RecallService.swift`
   - `Rockout/Views/Recall/RecallHomeView.swift`
   - `Rockout/Views/Recall/RecallTextInputView.swift`
   - `Rockout/Views/Recall/RecallVoiceInputView.swift`
   - `Rockout/Views/Recall/RecallImageInputView.swift`
   - `Rockout/Views/Recall/RecallResultsView.swift`

4. Build project (⌘B) to verify no errors

**Option B: Manual pbxproj Edit (Advanced)**
If you prefer to edit the project file directly, search for and remove all lines containing:
- `SoundPrint`
- `RockList`
- `soundprint_onboarding`
- `rocklist_onboarding`

Then add references for the new Recall files. This is error-prone and not recommended.

### 2. Run Database Migration

1. Open Supabase Dashboard
2. Go to SQL Editor
3. Copy contents of `sql/recall_schema.sql`
4. Paste and execute
5. Verify tables created:
   - `recall_events`
   - `recall_candidates`
   - `recall_confirmations`
   - `recall_crowd_posts`
   - `tracks`

### 3. Create Storage Bucket

1. In Supabase Dashboard, go to Storage
2. Click "New bucket"
3. Name: `recall-media`
4. **Public**: No (Private)
5. Click "Create bucket"
6. Go to "Policies" tab
7. Add RLS policies (see `docs/supabase/recall_storage_setup.md`)

### 4. Deploy Edge Functions

```bash
# Make sure you're logged in
supabase login

# Link to your project (if not already)
supabase link --project-ref YOUR_PROJECT_REF

# Deploy all functions
supabase functions deploy recall_create
supabase functions deploy recall_process
supabase functions deploy recall_confirm
supabase functions deploy recall_ask_crowd
```

### 5. Set Environment Variables

```bash
# Set OpenAI API key (required for recall_process)
supabase secrets set OPENAI_API_KEY="your-openai-api-key-here"

# Verify it's set
supabase secrets list
```

### 6. Test the Feature

1. Build and run the app in Xcode
2. Navigate to Recall tab
3. Test text input: "I heard this song in a TikTok"
4. Verify:
   - Recall created
   - Processing starts
   - Results appear with candidates
   - Confidence scores display
   - Sources button works
   - Confirm button works
   - Post to GreenRoom works

See `docs/recall-qa.md` for comprehensive testing guide.

## 🐛 Troubleshooting

### Build Errors

**Error: "Cannot find 'RecallHomeView' in scope"**
- Make sure Recall files are added to Xcode project
- Check Target Membership (should be "Rockout")

**Error: "No such module 'Supabase'"**
- Run `pod install` or update SPM packages

### Edge Function Errors

**Error: "OPENAI_API_KEY not configured"**
- Run: `supabase secrets set OPENAI_API_KEY="your-key"`

**Error: "Function not found"**
- Verify functions are deployed: `supabase functions list`
- Check function names match exactly

### Database Errors

**Error: "relation does not exist"**
- Run the SQL migration: `sql/recall_schema.sql`
- Verify tables exist in Supabase Dashboard

**Error: "permission denied"**
- Check RLS policies are applied
- Verify user is authenticated

### Storage Errors

**Error: "Bucket not found"**
- Create `recall-media` bucket in Supabase Dashboard
- Set it to Private

**Error: "Permission denied"**
- Add RLS policies for storage bucket
- See `docs/supabase/recall_storage_setup.md`

## 📝 Verification Checklist

After setup, verify:

- [ ] App builds without errors
- [ ] Recall tab appears in tab bar
- [ ] Text recall creates event and shows results
- [ ] Voice recall records, uploads, and processes
- [ ] Image recall performs OCR and processes
- [ ] Candidates display with confidence scores
- [ ] "Confirm" button saves confirmation
- [ ] "Post to GreenRoom" creates post
- [ ] "Ask the Crowd" creates post when confidence low
- [ ] Recent recalls list shows previous searches
- [ ] No references to SoundPrint/RockList in app

## 🚀 Next Steps

Once everything is working:

1. Test all input methods (text, voice, image)
2. Test edge cases (low confidence, errors)
3. Verify GreenRoom integration
4. Test on physical device (for voice/image)
5. Monitor Edge Function logs in Supabase Dashboard
6. Check database for proper data storage

## 📚 Documentation

- Implementation notes: `docs/recall-implementation-notes.md`
- Storage setup: `docs/supabase/recall_storage_setup.md`
- QA guide: `docs/recall-qa.md`
- Edge Functions: `supabase/functions/README.md`

