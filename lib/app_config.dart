/// Where found items are handed in and collected. Finders and claimants never
/// deal with each other directly; everything goes through this office.
const handoverPlace = 'Student Affairs Department';
const adminPhone = '0198186106';

/// true: only @student.uitm.edu.my Google accounts can sign in. To restore it,
/// also switch `member()` back in firestore.rules (see the comment there).
const studentsOnly = false;

/// OAuth "Web client" ID from Firebase (google-services.json → oauth_client
/// with client_type 3). Needed for "Sign in with Google".
const googleWebClientId = '765851912354-n8k9cnao614sarfto2sdm5if2i9hq8i7.apps.googleusercontent.com';
