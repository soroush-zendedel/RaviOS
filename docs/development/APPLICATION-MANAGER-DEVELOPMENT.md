# RaviOS Application Manager — سند توسعه کامل

تاریخ به‌روزرسانی: 2026-11-27  
وضعیت: پیاده‌سازی اولیه کامل و یکپارچه

این سند خلاصهٔ معماری، کارهای انجام‌شده، نحوهٔ استفاده، ساختار فایل‌ها و نقشهٔ راه توسعهٔ بعدی Application Manager در RaviOS است.

مراجع مرتبط:

- `application-manifast.md` — معماری و اصول declarative
- `application-manager-implementation.md` — یادداشت‌های پیاده‌سازی و جداول وضعیت

---

## ۱. هدف

RaviOS یک appliance مبتنی بر Buildroot + Docker است. Application Manager لایهٔ واحدی است که:

1. مانیفست declarative اپ‌ها را می‌خواند
2. منابع (display، GPU، audio، network، volume) را از طریق providerهای ماژولار resolve می‌کند
3. کانتینر را با baseline امنیتی یکسان اجرا می‌کند
4. هر ایمیج محلی داکر را بدون اسکریپت اختصاصی، از شل قابل‌اجرا می‌کند

**اصل کلیدی:** هیچ اسکریپت launch اختصاصی per-app وجود ندارد. یک runtime برای همه.

---

## ۲. کارهای انجام‌شده (نسبت به وضعیت اولیه)

### ۲.۱ از وضعیت اولیه تا الان

| حوزه | قبل | بعد |
|------|-----|-----|
| اجرای اپ | `ravios-app` ساده + `chromium-launch.sh` اختصاصی | فقط runtime عمومی |
| Chromium | `load_only` + پرچم‌های ناامن (`--no-sandbox` و …) | مسیر generic + `command` در مانیفست + baseline امن |
| منابع | hard-code در اسکریپت‌ها | providerهای display / gpu / audio / network / volume |
| مانیفست | فیلدهای پراکنده | بلوک `resources` + سازگاری با فیلدهای قدیمی |
| ایمیج دلخواه | پشتیبانی نداشت | قالب زنده سیستمی + `import` برای کپی اختصاصی |
| شبکه | پراکنده | پیش‌فرض مشترک `ravios-net` |
| volume | چند نام مختلف | الگوی `ravios-data-<cli>` + `--temp` |
| CLI | فقط `ravios-app start <name>` | symlink با `cli_name` (`chromium`, `webui`, …) |
| لاگ | نداشت | `--logs` / `ravios-app logs` (۳۳ خط آخر) |
| env | پارس شکننده | `environment` + `env_from_host` + TZ/LANG سراسری |
| محدودیت منابع | نداشت | `memory` / `cpus` / `cap_add` / `cap_drop` در مانیفست |

### ۲.۲ پاک‌سازی نهایی

حذف شده‌اند:

- `chromium-launch.sh` و نسخه `.orig`
- `try_auto_import` (جایگزین: `resolve_app_dir`)
- `resolve_image_for_cli` تکراری
- تعریف تکراری `sanitize_cli_name` در CLI
- منطق تکراری ساخت قالب (یک منبع: `render_default_manifest`)

---

## ۳. معماری اجرایی

```
کاربر تایپ می‌کند:  chromium   یا   python-3-14
        │
        ▼
 /usr/bin/<cli_name>  ──symlink──►  /usr/bin/ravios-app
        │
        ▼
 resolve_app_dir(name)
        │
        ├─► مانیفست اختصاصی؟  /var/lib/docker/ravios-apps/<name>/app.json
        │
        └─► در غیر این صورت: ایمیج محلی با نام sanitize‌شده؟
                 └─► رندر زنده از /etc/ravios/app-template.json
        │
        ▼
 providers (display/gpu/audio/network/volume)
        │
        ▼
 docker run  +  security baseline  +  command از مانیفست
```

### دو منبع مانیفست

| حالت | مسیر | اثر تغییر قالب سیستمی |
|------|------|-------------------------|
| Live default | `/etc/ravios/app-template.json` (در زمان اجرا) | فوری روی همهٔ ایمیج‌های بدون import |
| Materialised | `/var/lib/docker/ravios-apps/<cli>/app.json` | بی‌اثر؛ مانیفست اختصاصی است |

`ravios-app import` کپی قابل‌ویرایش می‌سازد. بدون import، فایل دائمی ساخته نمی‌شود.

---

## ۴. ساختار فایل‌ها

```
buildroot-external/rootfs-overlay/
├── etc/
│   ├── init.d/
│   │   └── S71ravios-app-cli          # ساخت symlinkهای CLI هنگام بوت
│   └── ravios/
│       └── app-template.json          # قالب پیش‌فرض سیستمی (قابل ویرایش)
└── usr/
    ├── bin/
    │   └── ravios-app                 # CLI + entry point
    └── libexec/ravios/
        ├── app-runtime.sh             # کتابخانه مشترک
        └── providers/
            ├── display.sh             # Wayland
            ├── gpu.sh                 # /dev/dri + گروه video
            ├── audio.sh               # PipeWire
            ├── network.sh             # شبکه نام‌دار + reference count
            └── volume.sh              # Docker volumes

artifacts/ravios-apps/
├── chromium/app.json
├── ollama/app.json
└── webui/app.json

docs/development/
├── application-manifast.md                      # معماری رسمی
├── application-manager-implementation.md        # یادداشت پیاده‌سازی
└── APPLICATION-MANAGER-DEVELOPMENT.md           # این سند
```

روی سیستم در حال اجرا، seed اپ‌ها معمولاً اینجاست:

```text
/var/lib/docker/ravios-apps/<cli_name>/app.json
```

---

## ۵. قالب سیستمی

مسیر: **`/etc/ravios/app-template.json`**  
Override مسیر: متغیر محیطی `RAVIOS_APP_TEMPLATE`

Placeholderها:

| Placeholder | مقدار جایگزینی |
|-------------|----------------|
| `{{cli_name}}` | نام CLI sanitize‌شده |
| `{{image}}` | مرجع ایمیج (مثلاً `python:3.14`) |
| `{{default_network}}` | پیش‌فرض `ravios-net` (`RAVIOS_DEFAULT_NETWORK`) |
| `{{volume_name}}` | `ravios-data-<cli_name>` |

ویرایش این فایل رفتار **همهٔ ایمیج‌های live-default** را عوض می‌کند.

---

## ۶. اسکیمای مانیفست (خلاصه)

```json
{
  "name": "myapp",
  "cli_name": "myapp",
  "version": "1.0.0",
  "image": "myimage:tag",
  "container": "myapp",
  "autostart": false,
  "restart": "no",
  "rm": false,
  "memory": "512m",
  "cpus": "1.0",
  "cap_add": [],
  "cap_drop": [],
  "ports": ["8080:8080"],
  "depends_on": ["otherapp"],
  "resources": {
    "display": false,
    "gpu": false,
    "audio": false,
    "networks": [{ "name": "ravios-net", "mode": "shared" }],
    "volumes": [{ "name": "ravios-data-myapp", "target": "/data", "persistent": true }]
  },
  "environment": { "KEY": "value" },
  "env_from_host": ["TZ", "LANG"],
  "command": ["binary", "--flag"],
  "pre_start": {
    "clear_locks": {
      "volume": "ravios-data-myapp",
      "paths": ["SingletonLock"]
    }
  }
}
```

فیلدهای قدیمی (`networks` / `volumes` سطح بالا، `environment`، `depends_on`) همچنان پشتیبانی می‌شوند.

---

## ۷. نحوهٔ استفاده

### دستورات اصلی

```sh
ravios-app list
ravios-app status [app]
ravios-app start <app> [--temp]
ravios-app stop <app>
ravios-app restart <app>
ravios-app remove <app>
ravios-app logs <app>
ravios-app import <image> [--name <cli>] [--update]
ravios-app import --scan [--yes]
ravios-app install-cli
```

### از طریق نام CLI

```sh
chromium
chromium --temp          # بدون volume پایدار
chromium --logs          # ۳۳ خط آخر لاگ
webui
ollama
python-3-14              # اگر ایمیج محلی باشد و مانیفست نداشته باشد → قالب زنده
```

### import در برابر live default

```sh
docker pull nginx:alpine
nginx-alpine             # اجرای با قالب زنده — فایل مانیفست دائمی ساخته نمی‌شود

ravios-app import nginx:alpine --name nginx-alpine
# از این به بعد مانیفست اختصاصی است و قابل ویرایش جداگانه
```

### محدودیت منابع در مانیفست

```json
"memory": "512m",
"cpus": "1.0",
"cap_drop": ["ALL"],
"cap_add": ["NET_BIND_SERVICE"]
```

### متغیرهای محیطی

1. `environment` در مانیفست (ثابت)
2. `env_from_host` (از میزبان، فقط اگر set باشد)
3. سراسری: `TZ` و `LANG` از میزبان مگر مانیفست override کند
4. خروجی providerها (`ENV:KEY=VALUE`)
5. `secret_key` برای WebUI

---

## ۸. امنیت

Baseline اعمال‌شده روی هر کانتینر:

- `--security-opt=no-new-privileges:true`

عمداً **اضافه نمی‌شود:**

- `CAP_SYS_ADMIN` / `CAP_SYS_PTRACE`
- `seccomp=unconfined` / `apparmor=unconfined`
- `--no-sandbox`
- `--ipc=host` (مگر نیاز تأیید‌شده در آینده)

Chromium باید روی User Namespace + پروفایل seccomp سفارشی میزبان کار کند (طبق `application-manifast.md`).

---

## ۹. یکپارچه‌سازی با build

فایل‌های overlay زیر `buildroot-external/rootfs-overlay/` در ایمیج روت RaviOS کپی می‌شوند.

Seed اپ‌ها (`artifacts/ravios-apps/`) باید مطابق pipeline فعلی پروژه به `/var/lib/docker/ravios-apps/` برسند (همان مسیر seed موجود).

`S71ravios-app-cli` بعد از آماده بودن Docker Data، symlinkهای `/usr/bin/<cli_name>` را می‌سازد.

---

## ۱۰. نقشهٔ راه توسعهٔ بعدی

### اولویت بالا

| مورد | توضیح |
|------|--------|
| تأیید Chromium بدون `--no-sandbox` | اجرای واقعی روی ایمیج RaviOS با seccomp فعلی |
| مهاجرت داده volumeهای قدیمی | در صورت وجود `ravios-chromium-data` / `ravi-ollama-models` روی سیستم‌های قبلی |
| تست integration | start/stop/import/--temp/--logs روی VM |

### اولویت متوسط

| مورد | توضیح |
|------|--------|
| JSON parser واقعی | جایگزینی sed برای objectهای تو در تو |
| Policy engine | لایهٔ authorize جدا از resolve (طبق بخش ۷ معماری) |
| Limits سراسری | سقف پیش‌فرض memory/cpu از یک فایل سیستمی |
| `.desktop` برای GUI | تولید از مانیفست برای اپ‌های display=true |

### اولویت پایین / آینده

| مورد | توضیح |
|------|--------|
| AppArmor | پس از پشتیبانی کرنل |
| لاگ پیشرفته | pager / follow / فیلتر؛ فعلاً ۳۳ خط کافی است |
| `import --update` دسته‌ای | به‌روزرسانی image برای چند اپ |
| providerهای USB / دستگاه | طبق بخش ۵.۶ معماری |

### قراردادهایی که نباید شکسته شوند

1. مانیفست host path، GID عددی یا فلگ خام Docker نداشته باشد
2. display / gpu / audio از هم جدا بمانند
3. شبکهٔ shared با stop یک اپ حذف نشود
4. volume پایدار با `remove` پاک نشود
5. اپ‌های بدون مانیفست اختصاصی از قالب سیستمی **زنده** تغذیه شوند
6. منطق اختصاصی یک اپ داخل core runtime نرود

---

## ۱۱. عیب‌یابی سریع

| علامت | بررسی |
|-------|--------|
| `unknown app` | ایمیج محلی با نام sanitize‌شده؟ `docker images` و `sanitize` |
| GUI باز نمی‌شود | `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR` در session |
| volume اعمال نشد | آیا `--temp` زده شده؟ |
| تغییر قالب اثری نداشت | آیا برای آن اپ `import` شده؟ منبع را با `ravios-app status` ببینید |
| symlink نیست | `ravios-app install-cli` یا بوت مجدد |

```sh
ravios-app status chromium
# source: manifest (...)  یا  default-template (/etc/ravios/app-template.json)
```

---

## ۱۲. متغیرهای محیطی سیستم

| متغیر | نقش | پیش‌فرض |
|-------|-----|---------|
| `RAVIOS_SEED_ROOT` | ریشه مانیفست‌های اختصاصی | `/var/lib/docker/ravios-apps` |
| `RAVIOS_STATE_DIR` | state داخلی | `/var/lib/ravios/apps` |
| `RAVIOS_APP_TEMPLATE` | مسیر قالب سیستمی | `/etc/ravios/app-template.json` |
| `RAVIOS_DEFAULT_NETWORK` | شبکه پیش‌فرض shared | `ravios-net` |
| `RAVIOS_TEMP` | داخلی؛ با `--temp` set می‌شود | `0` |

---

## ۱۳. جمع‌بندی

Application Manager فعلی:

- declarative و generic است
- با معماری `application-manifast.md` هم‌راستا است
- Chromium و اپ‌های seed را بدون launch script اختصاصی اجرا می‌کند
- هر ایمیج داکر محلی را با قالب زنده یا مانیفست اختصاصی پشتیبانی می‌کند
- نقاط گسترش (provider، policy، قالب سیستمی) بدون بازنویسی core قابل افزودن‌اند

برای جزئیات پروتکل provider و جداول وضعیت پیاده‌سازی به `application-manager-implementation.md` مراجعه کنید.
