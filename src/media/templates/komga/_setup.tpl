{{- /*
  Shared by komga--setup-job.yaml (post-install/upgrade hook) and
  komga--reconcile-cronjob.yaml (daily): the one container that does the whole
  idempotent Komga setup. See komga--setup-job.yaml for what it does.

  Call with the root context and indent the result under `containers:`:
    {{ include "komga.setupContainer" . | nindent 6 }}
*/ -}}
{{- define "komga.setupContainer" -}}
{{- $svc := print .Values.k8s.names.services.prefix .Values.komga.label .Values.k8s.names.services.suffix }}
{{- $lldapSvc := print .Values.k8s.names.services.prefix .Values.lldap.label .Values.k8s.names.services.suffix }}
{{- /* .root is a template-valued string (e.g. "{{ .Values.media.system.data.path }}/manga/bd")
   — resolve it with tpl before it goes anywhere near toJson, or it ships as literal text. */ -}}
{{- $libraries := list }}
{{- range .Values.komga.libraries }}
{{- $libraries = append $libraries (dict "name" .name "root" (tpl .root $)) }}
{{- end }}
- name: komga-setup
  image: python:3-alpine
  env:
  - name: KOMGA_URL
    value: "http://{{ $svc }}:{{ .Values.komga.ports.http.targetPort }}"
  - name: ADMIN_EMAIL
    value: "{{ .Values.komga.credentials.email }}"
  - name: ADMIN_PASSWORD
    value: "{{ .Values.komga.credentials.password }}"
  - name: CONVERT_TO_CBZ
    value: "{{ .Values.komga.convertToCbz }}"
  - name: LIBRARIES
    value: {{ $libraries | toJson | quote }}
  - name: ACCESS_GROUPS
    value: {{ .Values.komga.access.groups | toJson | quote }}
  - name: LLDAP_URL
    value: "http://{{ $lldapSvc }}:{{ .Values.lldap.ports.http.targetPort }}"
  - name: LLDAP_ADMIN_USER
    value: "{{ .Values.lldap.adminUser }}"
  - name: LLDAP_ADMIN_PASS
    value: "{{ .Values.lldap.adminPassword }}"
  - name: OIDC_ENABLED
    value: "{{ if .Values.komga.oidc.clientId }}true{{ else }}false{{ end }}"
  command:
  - python3
  - -c
  - |
    import base64, json, os, secrets, time, urllib.request, urllib.error

    BASE  = os.environ["KOMGA_URL"]
    EMAIL = os.environ["ADMIN_EMAIL"]
    PASSWORD = os.environ["ADMIN_PASSWORD"]
    CONVERT_TO_CBZ = os.environ["CONVERT_TO_CBZ"].lower() == "true"
    LIBRARIES = json.loads(os.environ["LIBRARIES"])
    ACCESS_GROUPS = json.loads(os.environ["ACCESS_GROUPS"])
    LLDAP_URL = os.environ["LLDAP_URL"]
    LLDAP_ADMIN_USER = os.environ["LLDAP_ADMIN_USER"]
    LLDAP_ADMIN_PASS = os.environ["LLDAP_ADMIN_PASS"]
    OIDC_ENABLED = os.environ["OIDC_ENABLED"].lower() == "true"
    ADMIN_GROUP = "admins"
    FULL_ADMIN_ROLES = {"ADMIN", "FILE_DOWNLOAD", "KOBO_SYNC", "KOREADER_SYNC", "PAGE_STREAMING", "USER"}
    BASE_ROLES = {"FILE_DOWNLOAD", "PAGE_STREAMING", "USER"}
    BASIC_AUTH = "Basic " + base64.b64encode(f"{EMAIL}:{PASSWORD}".encode()).decode()

    def call(method, path, body=None, headers=None, base=BASE):
        data = json.dumps(body).encode() if body is not None else None
        h = {"Content-Type": "application/json", **(headers or {})}
        req = urllib.request.Request(f"{base}{path}", data=data, method=method, headers=h)
        def parse(raw):
            try:    return json.loads(raw) if raw else None
            except Exception: return raw
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, parse(r.read().decode())
        except urllib.error.HTTPError as e:
            return e.code, parse(e.read().decode())

    # 1. wait for the API (claim-status is unauthenticated)
    for i in range(60):
        try:
            s, b = call("GET", "/api/v1/claim")
            if s == 200:
                print(f"  [{i}] Komga is up."); break
        except Exception as e:
            print(f"  [{i}] not ready: {e}")
        time.sleep(5)
    else:
        raise SystemExit("Komga never became ready")

    # 2. claim if unclaimed
    s, claim = call("GET", "/api/v1/claim")
    if s == 200 and isinstance(claim, dict) and not claim.get("isClaimed"):
        s, b = call("POST", "/api/v1/claim", headers={
            "X-Komga-Email": EMAIL, "X-Komga-Password": PASSWORD,
        })
        if s == 200:
            print(f"Server claimed, admin = {EMAIL}.")
        else:
            print(f"WARN: claim failed [{s}]: {b} — continuing, maybe a race with another run.")
    else:
        print("Server already claimed, skipping.")

    # 3. authenticate as admin
    s, existing = call("GET", "/api/v1/libraries", headers={"Authorization": BASIC_AUTH})
    if s == 401:
        print("WARN: 401 on GET /api/v1/libraries — komga.credentials doesn't match "
              "the real admin login (likely claimed by hand before this Job existed). "
              "Fix komga.credentials.email/password in values, or nothing below runs.")
        raise SystemExit(0)
    if s != 200 or not isinstance(existing, list):
        raise SystemExit(f"GET /api/v1/libraries failed [{s}]: {existing}")
    existing_names = {lib["name"] for lib in existing}
    print(f"Existing libraries: {sorted(existing_names) or '(none)'}")

    # 4. create missing libraries (never touch ones that already exist)
    for lib in LIBRARIES:
        if lib["name"] in existing_names:
            print(f"  '{lib['name']}' already exists, skipping.")
            continue
        body = {
            "name": lib["name"],
            "root": lib["root"],
            "convertToCbz": CONVERT_TO_CBZ,
            "analyzeDimensions": True,
            "emptyTrashAfterScan": True,
            "hashFiles": True,
            "hashKoreader": False,
            "hashPages": False,
            "importBarcodeIsbn": False,
            "importComicInfoBook": True,
            "importComicInfoCollection": True,
            "importComicInfoReadList": True,
            "importComicInfoSeries": True,
            "importComicInfoSeriesAppendVolume": False,
            "importEpubBook": False,
            "importEpubSeries": False,
            "importLocalArtwork": True,
            "importMylarSeries": False,
            "repairExtensions": True,
            "scanCbx": True,
            "scanDirectoryExclusions": [],
            "scanEpub": False,
            "scanForceModifiedTime": False,
            "scanInterval": "EVERY_6H",
            "scanOnStartup": True,
            "scanPdf": True,
            "seriesCover": "FIRST",
        }
        s, b = call("POST", "/api/v1/libraries", body, headers={"Authorization": BASIC_AUTH})
        if s in (200, 201):
            print(f"  created library '{lib['name']}' -> {lib['root']}")
        else:
            print(f"  WARN: failed to create '{lib['name']}' [{s}]: {b}")

    # 5. users: roles + library access, driven by LIVE LLDAP group membership
    def lldap_users():
        s, b = call("POST", "/auth/simple/login", {"username": LLDAP_ADMIN_USER, "password": LLDAP_ADMIN_PASS}, base=LLDAP_URL)
        if s != 200 or not isinstance(b, dict) or "token" not in b:
            print(f"  WARN: LLDAP login failed [{s}] — skipping user sync.")
            return None
        s, b = call("POST", "/api/graphql",
                    {"query": "{ users { id email groups { displayName } } }"},
                    headers={"Authorization": f"Bearer {b['token']}"}, base=LLDAP_URL)
        if s != 200 or not isinstance(b, dict) or "data" not in b:
            print(f"  WARN: LLDAP user query failed [{s}]: {b} — skipping user sync.")
            return None
        return b["data"]["users"]

    s, libs_now = call("GET", "/api/v1/libraries", headers={"Authorization": BASIC_AUTH})
    lib_ids = {l["name"]: l["id"] for l in libs_now} if s == 200 else {}
    s, komga_users = call("GET", "/api/v2/users", headers={"Authorization": BASIC_AUTH})
    ldap_users = lldap_users()
    if s != 200 or not isinstance(komga_users, list):
        print(f"  WARN: GET /api/v2/users failed [{s}]: {komga_users} — skipping user sync.")
    elif ldap_users is not None:
        # An account whose email is not an LLDAP user (e.g. the bootstrap
        # komga.credentials one) is never looked at. Nothing is ever deleted,
        # disabled, demoted or un-shared from a library by omission of a group.
        by_email = {u["email"].lower(): u for u in komga_users}
        for lu in sorted(ldap_users, key=lambda u: u["id"]):
            email = (lu.get("email") or "").strip()
            if not email:
                continue
            groups = {g["displayName"] for g in lu["groups"]}
            komga_groups = sorted(groups & set(ACCESS_GROUPS))
            is_admin = ADMIN_GROUP in groups
            user = by_email.get(email.lower())

            if user is None and not komga_groups:
                continue
            if komga_groups:
                names = sorted({n for g in komga_groups for n in ACCESS_GROUPS[g]})
                for n in names:
                    if n not in lib_ids:
                        print(f"  WARN: '{email}' ({komga_groups}) maps to unknown library '{n}' — ignored.")
                wanted_ids = sorted(lib_ids[n] for n in names if n in lib_ids)
            else:
                names = wanted_ids = None

            if user is None:
                # Pre-create so the first OIDC login lands on an account that
                # is already restricted. Random password: login is OIDC-only.
                roles = BASE_ROLES | (FULL_ADMIN_ROLES if is_admin else set())
                s, b = call("POST", "/api/v2/users",
                            {"email": email, "password": secrets.token_urlsafe(32), "roles": sorted(roles)},
                            headers={"Authorization": BASIC_AUTH})
                if s not in (200, 201) or not isinstance(b, dict):
                    print(f"  WARN: failed to create Komga user '{email}' [{s}]: {b}")
                    continue
                user = b
                print(f"  created Komga user '{email}' (roles {sorted(roles)}).")

            patch = {}
            if is_admin and not set(user["roles"]) >= FULL_ADMIN_ROLES:
                patch["roles"] = sorted(set(user["roles"]) | FULL_ADMIN_ROLES)
            if komga_groups:
                if user.get("sharedAllLibraries") is not False or set(user.get("sharedLibrariesIds", [])) != set(wanted_ids):
                    patch["sharedLibraries"] = {"all": False, "libraryIds": wanted_ids}
            elif not is_admin:
                print(f"  '{email}' has a Komga account but is in no komga_* group — left alone.")
            if not patch:
                print(f"  '{email}' already up to date.")
                continue
            s, b = call("PATCH", f"/api/v2/users/{user['id']}", patch, headers={"Authorization": BASIC_AUTH})
            if s == 204:
                print(f"  updated '{email}': " + ", ".join(
                    f"roles={patch['roles']}" if k == "roles" else f"libraries={names}" for k in patch))
            else:
                print(f"  WARN: failed to update '{email}' [{s}]: {b}")

    # 6. hide local login + auto-redirect into OIDC, only when OIDC is configured
    if OIDC_ENABLED:
        s, current = call("GET", "/api/v1/client-settings/global/list")
        if s != 200 or not isinstance(current, dict):
            print(f"  WARN: GET client-settings failed [{s}]: {current} — skipping.")
        else:
            wanted = {
                "webui.oauth2.hide_login": "true",
                "webui.oauth2.auto_login": "true",
            }
            patch = {
                k: {"value": v, "allowUnauthorized": True}
                for k, v in wanted.items()
                if current.get(k, {}).get("value") != v
            }
            if not patch:
                print("  OIDC hide-login/auto-login already set, skipping.")
            else:
                s, b = call("PATCH", "/api/v1/client-settings/global", patch,
                            headers={"Authorization": BASIC_AUTH})
                if s == 204:
                    print(f"  set client settings: {list(patch)}")
                else:
                    print(f"  WARN: failed to set client settings [{s}]: {b}")
    print("Komga setup complete.")
{{- end }}
