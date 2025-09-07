#!/usr/bin/env bash
set -euo pipefail

# --- Configuración ---
# Lee la versión desde package.json o app.json
if [ -f package.json ]; then
  VERSION=$(grep '"version"' package.json | head -n1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
elif [ -f app.json ]; then
  VERSION=$(grep '"version"' app.json | head -n1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
else
  echo "[error] No se encontró package.json ni app.json para leer la versión"
  exit 1
fi

# --- Selección de flavor ---
read -rp "Flavor (full/lite): " FLAVOR
if [[ "$FLAVOR" != "full" && "$FLAVOR" != "lite" ]]; then
  echo "[error] Flavor inválido"
  exit 1
fi

# --- Selección de track ---
read -rp "Track (internal/alpha/beta/production): " TRACK
if [[ ! "$TRACK" =~ ^(internal|alpha|beta|production)$ ]]; then
  echo "[error] Track inválido"
  exit 1
fi

# --- Construcción del tag ---
TAG="v${VERSION}-${FLAVOR}-${TRACK}"

# --- Confirmación ---
echo "[info] Tag generado: $TAG"
read -rp "¿Crear y pushear este tag? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "[cancelado] No se creó el tag"
  exit 0
fi

# --- Creación y push ---
git tag "$TAG"
git push origin "$TAG"

echo "[ok] Tag $TAG creado y enviado. El pipeline de GitHub Actions se ejecutará."
#!/usr/bin/env bash
set -euo pipefail

# --- Leer versión ---
if [ -f package.json ]; then
  VERSION=$(grep '"version"' package.json | head -n1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
elif [ -f app.json ]; then
  VERSION=$(grep '"version"' app.json | head -n1 | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
else
  echo "[error] No se encontró package.json ni app.json para leer la versión"
  exit 1
fi

# --- Selección de flavor ---
read -rp "Flavor (full/lite): " FLAVOR
if [[ "$FLAVOR" != "full" && "$FLAVOR" != "lite" ]]; then
  echo "[error] Flavor inválido"
  exit 1
fi

# --- Selección de track ---
read -rp "Track (internal/alpha/beta/production): " TRACK
if [[ ! "$TRACK" =~ ^(internal|alpha|beta|production)$ ]]; then
  echo "[error] Track inválido"
  exit 1
fi

# --- Construcción del tag ---
TAG="v${VERSION}-${FLAVOR}-${TRACK}"
echo "[info] Tag generado: $TAG"

# --- Validación de build ---
echo "[info] Validando build local antes de crear el tag..."
./gradlew :app:assemble${FLAVOR^}Release > build_check.log 2>&1 || {
  echo "[error] Falló el build. Revisa build_check.log"
  exit 1
}
echo "[ok] Build exitoso."

# --- Confirmación ---
read -rp "¿Crear y pushear este tag? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "[cancelado] No se creó el tag"
  exit 0
fi

# --- Creación y push ---
git tag "$TAG"
git push origin "$TAG"

echo "[ok] Tag $TAG creado y enviado. El pipeline de GitHub Actions se ejecutará."
name: Deploy Celconex to Play

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest

    env:
      ANDROID_KEYSTORE: ${{ secrets.ANDROID_KEYSTORE }}
      ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
      ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
      ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
      PLAY_SERVICE_JSON: ${{ secrets.PLAY_SERVICE_JSON }}
      FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4

      - name: Validate tag format
        run: |
          TAG="${GITHUB_REF_NAME}"
          if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-(full|lite)-(internal|alpha|beta|production)$ ]]; then
            echo "[error] Tag inválido: $TAG"
            exit 1
          fi
          echo "[ok] Tag válido: $TAG"

      - name: Extract flavor and track
        run: |
          TAG="${GITHUB_REF_NAME}"
          FLAVOR=$(echo $TAG | cut -d'-' -f2)
          TRACK=$(echo $TAG | cut -d'-' -f3)
          echo "FLAVOR=$FLAVOR" >> $GITHUB_ENV
          echo "TRACK=$TRACK" >> $GITHUB_ENV

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Install Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Decode keystore
        run: |
          echo "${ANDROID_KEYSTORE}" | base64 --decode > keystore.jks
          export ANDROID_KEYSTORE=$PWD/keystore.jks

      - name: Decode Play service JSON
        run: |
          echo "${PLAY_SERVICE_JSON}" | base64 --decode > play-service.json
          export PLAY_SERVICE_JSON=$PWD/play-service.json

      - name: Install Firebase CLI
        run: npm install -g firebase-tools

      # --- Validación extra en CI ---
      - name: Run tests
        run: |
          if npm run | grep -q "test"; then
            npm test
          else
            echo "[warn] No se encontró script de tests, saltando..."
          fi

      - name: Build release flavor
        run: ./gradlew :app:assemble${FLAVOR^}Release

      # --- Despliegue ---
      - name: Deploy to Play
        run: bash scripts/deploy_play.sh "$FLAVOR" "$TRACK"
// firestore.rules
match /releaseLogs/{docId} {
  allow read: if request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == "admin";
  allow write: if false; // Solo Functions escriben
}
// components/ReleaseLogsTable.tsx
import { useEffect, useState } from "react";
import { collection, query, orderBy, onSnapshot } from "firebase/firestore";
import { db } from "../firebase"; // tu inicialización

type ReleaseLog = {
  flavor: string;
  track: string;
  versionCode: string;
  versionName: string;
  commit: string;
  date: string;
  ts?: any;
};

export default function ReleaseLogsTable() {
  const [logs, setLogs] = useState<ReleaseLog[]>([]);

  useEffect(() => {
    const q = query(collection(db, "releaseLogs"), orderBy("ts", "desc"));
    const unsub = onSnapshot(q, (snap) => {
      setLogs(snap.docs.map((d) => ({ id: d.id, ...d.data() } as ReleaseLog)));
    });
    return () => unsub();
  }, []);

  return (
    <div style={{ padding: 20 }}>
      <h2>Historial de despliegues</h2>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr>
            <th>Fecha</th>
            <th>Flavor</th>
            <th>Track</th>
            <th>Versión</th>
            <th>Commit</th>
          </tr>
        </thead>
        <tbody>
          {logs.map((log) => (
            <tr key={log.id}>
              <td>{log.ts?.toDate().toLocaleString() ?? log.date}</td>
              <td>{log.flavor}</td>
              <td>{log.track}</td>
              <td>{log.versionName} ({log.versionCode})</td>
              <td>
                <a
                  href={`https://github.com/<tu-org>/<tu-repo>/commit/${log.commit}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {log.commit}
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
// components/ReleaseLogsTable.tsx
import { useEffect, useState } from "react";
import { collection, query, orderBy, onSnapshot } from "firebase/firestore";
import { db } from "../firebase"; // tu inicialización

type ReleaseLog = {
  flavor: string;
  track: string;
  versionCode: string;
  versionName: string;
  commit: string;
  date: string;
  ts?: any;
};

export default function ReleaseLogsTable() {
  const [logs, setLogs] = useState<ReleaseLog[]>([]);

  useEffect(() => {
    const q = query(collection(db, "releaseLogs"), orderBy("ts", "desc"));
    const unsub = onSnapshot(q, (snap) => {
      setLogs(snap.docs.map((d) => ({ id: d.id, ...d.data() } as ReleaseLog)));
    });
    return () => unsub();
  }, []);

  return (
    <div style={{ padding: 20 }}>
      <h2>Historial de despliegues</h2>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr>
            <th>Fecha</th>
            <th>Flavor</th>
            <th>Track</th>
            <th>Versión</th>
            <th>Commit</th>
          </tr>
        </thead>
        <tbody>
          {logs.map((log) => (
            <tr key={log.id}>
              <td>{log.ts?.toDate().toLocaleString() ?? log.date}</td>
              <td>{log.flavor}</td>
              <td>{log.track}</td>
              <td>{log.versionName} ({log.versionCode})</td>
              <td>
                <a
                  href={`https://github.com/<tu-org>/<tu-repo>/commit/${log.commit}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {log.commit}
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
// components/ReleaseLogsTable.tsx
import { useEffect, useState } from "react";
import { collection, query, orderBy, onSnapshot } from "firebase/firestore";
import { db } from "../firebase"; // tu inicialización

type ReleaseLog = {
  flavor: string;
  track: string;
  versionCode: string;
  versionName: string;
  commit: string;
  date: string;
  ts?: any;
};

export default function ReleaseLogsTable() {
  const [logs, setLogs] = useState<ReleaseLog[]>([]);

  useEffect(() => {
    const q = query(collection(db, "releaseLogs"), orderBy("ts", "desc"));
    const unsub = onSnapshot(q, (snap) => {
      setLogs(snap.docs.map((d) => ({ id: d.id, ...d.data() } as ReleaseLog)));
    });
    return () => unsub();
  }, []);

  return (
    <div style={{ padding: 20 }}>
      <h2>Historial de despliegues</h2>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr>
            <th>Fecha</th>
            <th>Flavor</th>
            <th>Track</th>
            <th>Versión</th>
            <th>Commit</th>
          </tr>
        </thead>
        <tbody>
          {logs.map((log) => (
            <tr key={log.id}>
              <td>{log.ts?.toDate().toLocaleString() ?? log.date}</td>
              <td>{log.flavor}</td>
              <td>{log.track}</td>
              <td>{log.versionName} ({log.versionCode})</td>
              <td>
                <a
                  href={`https://github.com/<tu-org>/<tu-repo>/commit/${log.commit}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {log.commit}
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
admin.initializeApp();

export const logRelease = functions.https.onCall(async (data, context) => {
  if (!context.auth && !process.env.ALLOW_ANON_RELEASE_LOG) {
    throw new functions.https.HttpsError("unauthenticated", "Auth required");
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const logData = {
    flavor: data.flavor,
    track: data.track,
    versionCode: data.versionCode,
    versionName: data.versionName,
    commit: data.commit,
    date: data.date,
    status: data.status ?? "success", // success | failed
    duration: data.duration ?? null,  // en segundos o ms
    ts: now
  };

  await db.collection("releaseLogs").add(logData);
  return { ok: true };
});
# Limpia build previa
./gradlew :app:clean

# Compila flavor y tipo release
./gradlew :app:bundleFullRelease   # o :app:bundleLiteRelease

# El .aab quedará en:
# android/app/build/outputs/bundle/fullRelease/app-full-release.aab
# android/app/build/outputs/bundle/liteRelease/app-lite-release.aab
<th>Estado</th>
<th>Duración</th>
...
<td style={{color: log.status === 'success' ? 'green' : 'red'}}>
  {log.status}
</td>
<td>{log.duration ? `${log.duration}s` : '-'}</td>
#!/usr/bin/env bash
set -euo pipefail

# --- Validación de entorno ---
REQUIRED_VARS=(ANDROID_KEYSTORE ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD PLAY_SERVICE_JSON FIREBASE_TOKEN)
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "[error] Falta variable de entorno: $var"
    exit 1
  fi
done

# --- Parámetros ---
FLAVOR="${1:-full}"       # full o lite
TRACK="${2:-internal}"    # internal, alpha, beta, production
UPLOAD="${3:-yes}"        # yes para subir a Play, no para solo generar .aab

DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT=$(git rev-parse --short HEAD)
VERSION_CODE=$(date +%y%j%H%M)
VERSION_NAME="1.0.${VERSION_CODE}+$GIT"

echo "[info] === Celconex Release ==="
echo "[info] Flavor: $FLAVOR | Track: $TRACK | Upload: $UPLOAD"
echo "[info] versionCode=$VERSION_CODE versionName=$VERSION_NAME"
echo "[info] Commit=$GIT Fecha=$DATE"

START_TS=$(date +%s)

# --- Build ---
./gradlew :app:clean
./gradlew :app:bundle${FLAVOR^}Release \
  -PversionCode=$VERSION_CODE \
  -PversionName=$VERSION_NAME

# --- Ruta del AAB ---
AAB_PATH=$(find android/app/build/outputs/bundle/${FLAVOR}Release -name "*.aab" | head -n1)
echo "[ok] AAB generado en: $AAB_PATH"

# --- Subida opcional a Play ---
if [ "$UPLOAD" = "yes" ]; then
  ./gradlew :app:publish${FLAVOR^}ReleaseBundle -Ptrack=$TRACK
  STATUS="success"
else
  echo "[info] Subida a Play saltada."
  STATUS="manual"
fi

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

# --- Log en Firestore ---
firebase functions:call logRelease \
  --data "{
    \"flavor\":\"$FLAVOR\",
    \"track\":\"$TRACK\",
    \"versionCode\":\"$VERSION_CODE\",
    \"versionName\":\"$VERSION_NAME\",
    \"commit\":\"$GIT\",
    \"date\":\"$DATE\",
    \"status\":\"$STATUS\",
    \"duration\":$DURATION
  }"

echo "[done] Release completado en ${DURATION}s"
