---
title: Let's Talk App - Layman Diagram with Security
---

```mermaid
flowchart TD
    A([User opens Let's Talk App])
    B([User selects language, enters text, or records audio])
    C([App sends request to Backend (Cloud Function)])
    D1([Google Neural2 TTS])
    D2([Narakeet TTS])
    E([Gemini Translation API])
    F([Audio/Text returned to App])
    G([Audio/Text stored in local cache (device)])
    H([Audio/Text stored in cloud cache (Firebase Storage/Firestore)])
    I([User history & Learn tab updated])
    J([Credits & user info updated])

    %% Security Features
    S1([Anonymous Firebase Auth: User identity])
    S2([Firestore Rules: Only user can access their data])
    S3([ID Token: Secure backend requests])
    S4([Secret Manager: Protects API keys])
    S5([Audio/Text only stored for user])

    A --> B
    B --> C
    C -->|If language is UK English, French, German, Mandarin, Hindi, Urdu, Portuguese| D1
    C -->|Other languages| D2
    C --> E
    D1 --> F
    D2 --> F
    E --> F
    F --> G
    F --> H
    G --> I
    H --> I
    I --> J

    %% Security
    A --> S1
    C --> S3
    H --> S2
    C --> S4
    H --> S5
    G --> S5
    I --> S2
    J --> S2
```

**How to view:**
- Open this file in VS Code with the "Markdown Preview Mermaid Support" extension, or
- Paste the diagram code at https://mermaid.live to generate an image.
