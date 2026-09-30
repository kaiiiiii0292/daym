# FlexShare

FlexShare is a PSU campus equipment marketplace built with Flutter and Supabase. The app includes a borrower feed, a lender listing view, an OpenStreetMap campus map, and a verified-lender listing flow.

## Local setup

Install Flutter 3.27 or newer, then create the Android, iOS, and web scaffolding and fetch dependencies:

```sh
flutter create . --platforms=android,ios,web
flutter pub get
```

The QR handoff flow uses the device camera. Add camera permission text to the generated native projects before building: `CAMERA` in Android's `AndroidManifest.xml`, and `NSCameraUsageDescription` in iOS's `Info.plist`.

Apply the SQL migrations in `supabase/migrations` to a Supabase project. With the Supabase CLI installed and the project linked, use `supabase db push`.

Run the web app with the project's public URL and anon key. Never put a service-role key in the client:

```sh
flutter run -d chrome \
	--dart-define=SUPABASE_URL=https://your-project.supabase.co \
	--dart-define=SUPABASE_ANON_KEY=your-public-anon-key
```

Without those defines, the app opens in preview mode with local sample listings. The campus map uses OpenStreetMap tiles and needs an internet connection.

The `Deploy FlexShare preview` GitHub Actions workflow builds and publishes a web preview to GitHub Pages on pushes to `main` or manual dispatch. With no `SUPABASE_URL` and `SUPABASE_ANON_KEY` repository secrets configured, it runs in preview-data mode only. Configure those public client values as Actions secrets to connect a Supabase project; do not add service-role or payment-provider secrets to the Flutter build.

## Access and payment

New accounts start as unverified borrowers. A trusted PSU verification process must set `is_id_verified` and assign lender or FlexRunner roles; the Flutter client cannot grant itself those privileges. Verified borrowers can submit rental requests through the database RPC. Requests reserve the item and record a GCash or Maya preference, but payment collection and lender confirmation still need a trusted backend workflow.

Checkout currently supports hourly/daily units, none/standard/plus protection tiers, self-meetup or an ₱80 classroom courier request, and a 12% owner-side commission. Wallet choices create pending checkout records only; connect GCash/Maya through a payment provider and confirm settlement from a trusted webhook before treating rentals as paid. QR handoffs and courier jobs unlock only after payment confirmation. Pickup and return require different verified participants to issue/scan the one-time QR and submit the mandatory condition photo.
# daym