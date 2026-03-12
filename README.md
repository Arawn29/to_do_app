Offline-First task management and planning application. This project seamlessly bridges the gap between local speed and cloud reliability by combining SQLite (Sqflite) for local persistence and Firebase Firestore for real-time synchronization.
✨ Key Features
 🔄 Intelligent Sync: Real-time data synchronization between your mobile device and desktop using Firebase Firestore.
 💾 Offline-First Architecture: Your notes are saved locally first. Work without an internet connection and sync automatically once you're back online.
 📂 Nested Folders: Organize your tasks into a hierarchical structure with infinite folder nesting support.
 🎯 Priority System: Color-coded task prioritization (High, Medium, Low) to keep you focused on what matters most.
 📅 Calendar Integration: Add reminders that automatically sync with your device’s native calendar.
 🌓 Adaptive Theme: Fully supports Material 3 Dynamic Color, including a crisp Dark Mode and a vibrant Light Mode.
 🖱️ Drag & Drop: Intuitive UI allowing you to move tasks between folders or drop them into the "Smart Trash" for deletion.
 🎉 Celebration Effects: Haptic feedback and confetti bursts upon completing tasks to keep you motivated!
 🛠️ Technical StackFrontend: Flutter (Material 3)Local Persistence: Sqflite (with FFI support for Windows/Linux)Backend/Authentication: Firebase (Firestore & Auth)State Maagement: ValueNotifier & StreamBuilderExternal Integrations: Add 2 Calendar, UUID, Confetti, 
 Path Provider🚀 Getting StartedPrerequisitesFlutter SDK installed on your machine.A Firebase project created in the Firebase Console.InstallationClone the repository:Bashgit clone https://github.com/[YOUR_USERNAME]/synco-todo.git
Install dependencies:Bashflutter pub get
Configure Firebase:Ensure you have the FlutterFire CLI installed and run:Bashflutterfire configure
Run the application:Bashflutter run
🏗️ Architecture InsightThe application utilizes a Repository Pattern combined with a Local-First strategy. Data is initially written to the local SQLite database to ensure zero-latency user interaction. A background StreamSubscription then pushes these changes to Firestore while simultaneously listening for external updates (e.g., from a desktop client), ensuring all your devices stay in perfect harmony.📸 UI PreviewLight ModeDark ModeDeveloped by: [Your Name]Find me on [LinkedIn] or [X/Twitter]Quick Tip: If you want to impress recruiters even more, you can add a "License" section (like MIT License) at the bottom.Would you like me to help you write a "Technical Challenges" section for the README where we explain how we handled the Windows/Android cross-platform database differences?
