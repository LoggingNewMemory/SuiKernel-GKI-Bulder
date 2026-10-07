#!/usr/bin/env bash
# SuiKernelManager.sh - Patches KSUN to support SuiKernel Manager as a secondary Manager

KERNEL_DIR="$1"
if [ -z "$KERNEL_DIR" ]; then
    echo "Usage: ./SuiKernelManager.sh <kernel_directory>"
    exit 1
fi

KSUN_DIR="$KERNEL_DIR/KernelSU-Next"

echo "[+] Patching KernelSU-Next for SuiKernel Dual-Manager Support in $KSUN_DIR"

python3 - "$KSUN_DIR" << 'PYEOF'
import sys
import os

ksun_dir = sys.argv[1]

APK_SIGN       = os.path.join(ksun_dir, "kernel/manager/apk_sign.c")
MANAGER_ID     = os.path.join(ksun_dir, "kernel/manager/manager_identity.h")
THRONE_TRACKER = os.path.join(ksun_dir, "kernel/manager/throne_tracker.c")

SUI_PKG     = "kanagawa.yamada.suikernel.manager"
SUI_PKG_LEN = str(len(SUI_PKG))

def read(path):
    with open(path, "r") as f:
        return f.read()

def write(path, content):
    with open(path, "w") as f:
        f.write(content)

def patch(path, target, replacement, label):
    content = read(path)
    if target not in content:
        print(f"  [!] {label}: target not found — skipping (already patched or source changed)")
        return
    write(path, content.replace(target, replacement, 1))
    print(f"  [+] {label}")

# Verify all files exist before touching anything
for f in [APK_SIGN, MANAGER_ID, THRONE_TRACKER]:
    if not os.path.exists(f):
        print(f"[-] Cannot find {f}", file=sys.stderr)
        sys.exit(1)

# ============================================================
# PATCH 1 — apk_sign.c
# Make is_manager_apk() return true for SuiKernel Manager by
# package name, before the signature check runs.
# ============================================================
print("[*] Patch 1: apk_sign.c — package name bypass")

patch(
    APK_SIGN,
    target = "bool is_manager_apk(char *path)\n{",
    replacement = """bool is_manager_apk(char *path)
{
	// SuiKernel Manager: bypass signature check by package name
	char sui_pkg[KSU_MAX_PACKAGE_NAME];
	char dir_path[512];
	char *last_slash;
	
	strscpy(dir_path, path, sizeof(dir_path));
	last_slash = strrchr(dir_path, '/');
	if (last_slash) *last_slash = '\\0';

	if (get_pkg_from_apk_dir_path(sui_pkg, dir_path) >= 0) {
		if (strncmp(sui_pkg, "SUI_PKG", SUI_PKG_LEN) == 0) {
			pr_info("SuiKernel: Manager detected! Granting native rights.\\n");
			return true;
		}
	}""".replace("SUI_PKG_LEN", SUI_PKG_LEN).replace("SUI_PKG", SUI_PKG),
    label = "is_manager_apk() bypass injected",
)

# ============================================================
# PATCH 2 — manager_identity.h
# Add ksu_sui_manager_appid as a second manager UID slot.
# Extend is_manager() and is_uid_manager() to check both UIDs.
# Add helper functions for the SuiKernel Manager UID.
# ============================================================
print("[*] Patch 2: manager_identity.h — dual manager UID support")

# 2a. Add extern declaration for ksu_sui_manager_appid
patch(
    MANAGER_ID,
    target      = "extern uid_t ksu_manager_appid; // DO NOT DIRECT USE",
    replacement = "extern uid_t ksu_manager_appid;     // DO NOT DIRECT USE\n"
                  "extern uid_t ksu_sui_manager_appid; // SuiKernel Manager -- DO NOT DIRECT USE",
    label       = "extern ksu_sui_manager_appid added",
)

# 2b. Update is_manager() to check both UIDs
patch(
    MANAGER_ID,
    target = """static inline bool is_manager()
{
    return unlikely(ksu_manager_appid == current_uid().val % KSU_PER_USER_RANGE);
}""",
    replacement = """static inline bool is_manager()
{
    uid_t appid = current_uid().val % KSU_PER_USER_RANGE;
    return unlikely(ksu_manager_appid == appid) ||
           unlikely(ksu_sui_manager_appid == appid);
}""",
    label = "is_manager() extended to check both UIDs",
)

# 2c. Update is_uid_manager() to check both UIDs
patch(
    MANAGER_ID,
    target = """static inline bool is_uid_manager(uid_t uid)
{
    return unlikely(ksu_manager_appid == uid % KSU_PER_USER_RANGE);
}""",
    replacement = """static inline bool is_uid_manager(uid_t uid)
{
    uid_t appid = uid % KSU_PER_USER_RANGE;
    return unlikely(ksu_manager_appid == appid) ||
           unlikely(ksu_sui_manager_appid == appid);
}""",
    label = "is_uid_manager() extended to check both UIDs",
)

# 2d. Add SuiKernel Manager helper functions before the closing #endif
patch(
    MANAGER_ID,
    target      = "#endif // __KSU_H_MANAGER_IDENTITY",
    replacement = """static inline bool ksu_is_sui_manager_appid_valid()
{
    return ksu_sui_manager_appid != KSU_INVALID_APPID;
}

static inline uid_t ksu_get_sui_manager_appid()
{
    return ksu_sui_manager_appid;
}

static inline void ksu_set_sui_manager_appid(uid_t appid)
{
    ksu_sui_manager_appid = appid;
}

static inline void ksu_invalidate_sui_manager_uid()
{
    ksu_sui_manager_appid = KSU_INVALID_APPID;
}
#endif // __KSU_H_MANAGER_IDENTITY""",
    label = "SuiKernel Manager helper functions added",
)

# ============================================================
# PATCH 3 — throne_tracker.c
# 1. Define ksu_sui_manager_appid global variable
# 2. Add crown_sui_manager() function
# 3. In my_actor(): route SuiKernel Manager to crown_sui_manager()
#    (keep scanning) and official KSUN manager to crown_manager() (stop)
# 4. In track_throne(): validate and invalidate both manager UIDs
# ============================================================
print("[*] Patch 3: throne_tracker.c — dual manager tracking")

# 3a. Define the second UID variable right after the first
patch(
    THRONE_TRACKER,
    target      = "uid_t ksu_manager_appid = KSU_INVALID_APPID;",
    replacement = "uid_t ksu_manager_appid     = KSU_INVALID_APPID;\n"
                  "uid_t ksu_sui_manager_appid = KSU_INVALID_APPID;",
    label       = "ksu_sui_manager_appid global variable defined",
)

# 3b. Add crown_sui_manager() right before crown_manager()
patch(
    THRONE_TRACKER,
    target = "static void crown_manager(const char *apk, struct list_head *uid_data)\n{",
    replacement = """static void crown_sui_manager(const char *apk, struct list_head *uid_data)
{
	char pkg[KSU_MAX_PACKAGE_NAME];
	char dir_path[512];
	char *last_slash;

	strscpy(dir_path, apk, sizeof(dir_path));
	last_slash = strrchr(dir_path, '/');
	if (last_slash) *last_slash = '\\0';

	if (get_pkg_from_apk_dir_path(pkg, dir_path) < 0) {
		pr_err("Failed to get package name from apk path: %s\\n", apk);
		return;
	}

	pr_info("SuiKernel Manager pkg: %s\\n", pkg);

	struct list_head *list = (struct list_head *)uid_data;
	struct uid_data *np;

	list_for_each_entry (np, list, list) {
		if (strncmp(np->package, pkg, KSU_MAX_PACKAGE_NAME) == 0) {
			pr_info("Crowning SuiKernel Manager: %s(uid=%d)\\n", pkg, np->uid);
			ksu_set_sui_manager_appid(np->uid);
			break;
		}
	}
}

static void crown_manager(const char *apk, struct list_head *uid_data)
{""",
    label = "crown_sui_manager() function added",
)

# 3c. In search_manager(): split handling — SuiKernel keeps scanning, official stops
patch(
    THRONE_TRACKER,
    target = """			bool is_manager = is_manager_apk(candidate_path);
			pr_info("Found manager base.apk at path: %s, is_manager: %d\\n", candidate_path, is_manager);

			// Only crown if verification passes
			if (unlikely(!is_manager))
				goto skip_iterate;

			// Verified manager found, halt outer loop
			stop = 1;
			crown_manager(candidate_path, uid_data);""",
    replacement = """			bool is_manager = is_manager_apk(candidate_path);
			pr_info("Found manager base.apk at path: %s, is_manager: %d\\n", candidate_path, is_manager);

			// Only crown if verification passes
			if (unlikely(!is_manager))
				goto skip_iterate;

			char _pkg[KSU_MAX_PACKAGE_NAME];
			char _dir_path[512];
			char *_last_slash;

			strscpy(_dir_path, candidate_path, sizeof(_dir_path));
			_last_slash = strrchr(_dir_path, '/');
			if (_last_slash) *_last_slash = '\\0';

			if (get_pkg_from_apk_dir_path(_pkg, _dir_path) == 0 &&
			    strncmp(_pkg, "SUI_PKG", SUI_PKG_LEN) == 0) {
				crown_sui_manager(candidate_path, uid_data);
			} else {
				crown_manager(candidate_path, uid_data);
			}
			// We remove stop = 1 to keep searching in case both managers exist""".replace("SUI_PKG_LEN", SUI_PKG_LEN).replace("SUI_PKG", SUI_PKG),
    label = "search_manager() dual-crown routing added",
)

# 3d. In track_throne(): validate and invalidate both manager UIDs independently
patch(
    THRONE_TRACKER,
    target = """	// first, check if manager_uid exist!
	uid_t manager_package_uid = KSU_INVALID_APPID;
	bool need_rescan = false;
	list_for_each_entry (np, &uid_list, list) {
#ifdef KSU_MANAGER_PACKAGE
		if (strcmp(np->package, KSU_MANAGER_PACKAGE) == 0) {
			manager_package_uid = np->uid;
			break;
		}
#else
		if (np->uid == ksu_get_manager_appid()) {
			manager_package_uid = np->uid;
			break;
		}
#endif
	}

	if (manager_package_uid == KSU_INVALID_APPID) {
		cached_manager_apk_path[0] = 0;
		if (ksu_is_manager_appid_valid()) {
			pr_info("manager is uninstalled, invalidate it!\\n");
			ksu_invalidate_manager_uid();
			goto prune;
		}
#ifndef KSU_MANAGER_PACKAGE
		// Unpinned: package name unknown; rescan to find it
		need_rescan = true;
#endif
	} else {
		if (!ksu_is_manager_appid_valid()) {
			need_rescan = true;
		} else if (unlikely(np->uid != ksu_get_manager_appid())) {
			// this should not happen in normal android system
			pr_info("manager uid changed, invalidate it!\\n");
			cached_manager_apk_path[0] = 0;
			ksu_invalidate_manager_uid();
			need_rescan = true;
		} else {
			// uid unchanged, skip
			pr_info("manager uid unchanged, skip search!\\n");
		}
	}

	if (need_rescan) {
		// If the apk path still exists, the verification result won't be changed
		if (cached_manager_apk_path[0]) {
			struct path p;
			int ret = kern_path(cached_manager_apk_path, 0, &p);
			if (ret == 0) {
				// skip search
				pr_info("manager apk path unchanged, skip search!\\n");
				path_put(&p);
				goto prune;
			} else if (ret != -ENOENT) {
				pr_err("stat cached manager path failed: %d (path=%s)\\n", ret, cached_manager_apk_path);
			}
		}
#ifdef KSU_MANAGER_PACKAGE
		pr_info("Searching manager " KSU_MANAGER_PACKAGE "...\\n");
#else
		pr_info("Searching manager...\\n");
#endif
		search_manager("/data/app", 2, &uid_list);
		pr_info("Search manager finished\\n");
	}""",
    replacement = """	// first, check if manager_uid exist! (both official and SuiKernel)
	uid_t manager_package_uid = KSU_INVALID_APPID;
	uid_t sui_manager_package_uid = KSU_INVALID_APPID;
	bool need_rescan = false;
	list_for_each_entry (np, &uid_list, list) {
#ifdef KSU_MANAGER_PACKAGE
		if (strcmp(np->package, KSU_MANAGER_PACKAGE) == 0) {
			manager_package_uid = np->uid;
		}
#else
		if (np->uid == ksu_get_manager_appid()) {
			manager_package_uid = np->uid;
		}
#endif
		if (np->uid == ksu_get_sui_manager_appid()) {
			sui_manager_package_uid = np->uid;
		}
	}

	if (manager_package_uid == KSU_INVALID_APPID) {
		cached_manager_apk_path[0] = 0;
		if (ksu_is_manager_appid_valid()) {
			pr_info("manager is uninstalled, invalidate it!\\n");
			ksu_invalidate_manager_uid();
		}
#ifndef KSU_MANAGER_PACKAGE
		// Unpinned: package name unknown; rescan to find it
		need_rescan = true;
#endif
	} else {
		if (!ksu_is_manager_appid_valid()) {
			need_rescan = true;
		} else if (unlikely(manager_package_uid != ksu_get_manager_appid())) {
			pr_info("manager uid changed, invalidate it!\\n");
			cached_manager_apk_path[0] = 0;
			ksu_invalidate_manager_uid();
			need_rescan = true;
		}
	}

	if (sui_manager_package_uid == KSU_INVALID_APPID) {
		if (ksu_is_sui_manager_appid_valid()) {
			pr_info("SuiKernel Manager is uninstalled, invalidate it!\\n");
			ksu_invalidate_sui_manager_uid();
		}
		need_rescan = true;
	} else {
		if (!ksu_is_sui_manager_appid_valid()) {
			need_rescan = true;
		} else if (unlikely(sui_manager_package_uid != ksu_get_sui_manager_appid())) {
			pr_info("SuiKernel Manager uid changed, invalidate it!\\n");
			ksu_invalidate_sui_manager_uid();
			need_rescan = true;
		}
	}

	if (need_rescan) {
		pr_info("Searching for managers...\\n");
		search_manager("/data/app", 2, &uid_list);
		pr_info("Search managers finished\\n");
	}""",
    label = "track_throne() dual manager exist check updated",
)

print()
print("[+] All patches applied! SuiKernel Manager dual-manager support is ready.")
PYEOF