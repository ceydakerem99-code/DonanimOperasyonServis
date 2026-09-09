const admin = require("firebase-admin");

admin.initializeApp({
  projectId: "donanimoperasyonservis",
});

async function main() {
  const email = "beyzakerem@dops.com";
  const password = "123beyza";

  const user = await admin.auth().getUserByEmail(email);

  await admin.auth().updateUser(user.uid, {
    password,
  });

  console.log(`✅ Şifre güncellendi: ${email}`);
  console.log(`UID: ${user.uid}`);

  await admin.app().delete();
}

main().catch(async (error) => {
  console.error("❌ Şifre güncellenemedi:", error);
  try {
    await admin.app().delete();
  } catch {}
  process.exit(1);
});
