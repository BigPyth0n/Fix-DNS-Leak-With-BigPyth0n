# 🛡️ Fix DNS Leak Script (برای اوبونتو)

این اسکریپت `setdns.sh` برای رفع مشکل DNS Leak در اوبونتو 20.04 و بالاتر طراحی شده است. به شما کمک می‌کند مطمئن شوید که **فقط DNSهای مربوط به موقعیت فعلی سرور** مورد استفاده قرار می‌گیرند و هیچ نشتی DNS به خارج از کشور سرور وجود ندارد.

---

## 🎯 کاربرد اسکریپت

✅ نصب و پیکربندی `resolvconf`  
✅ تنظیم دقیق `systemd-resolved`  
✅ تصحیح خطای متداول `sudo: unable to resolve host`  
✅ جلوگیری کامل از نشتی DNS (DNS Leak)  
✅ شناسایی خودکار hostname و به‌روزرسانی `/etc/hosts`  
✅ نمایش خودکار نتیجه تست `Extended DNS Leak Test`

---

## ⚠️ نکته مهم

> اگر سرور شما از ترکیه به مکان دیگری منتقل شود، باید DNS مربوط به **مکان جدید سرور** به‌روزرسانی شود. استفاده از DNS یک کشور دیگر باعث لو رفتن اطلاعات و لوکیشن شما در تست‌ها خواهد شد.

---

## ⚙️ پیش‌نیازها

- Ubuntu 20.04 یا بالاتر  
- دسترسی `sudo`  
- اتصال اینترنت  
- curl

---

## 🚀 نحوه دانلود و اجرای مستقیم از GitHub

### 1. دریافت فایل بدون کش (با curl):

```bash
curl -H 'Cache-Control: no-cache' -L https://raw.githubusercontent.com/BigPyth0n/Fix-DNS-Leak-With-GPT/main/setdns.sh -o setdns.sh
```

### 2. دادن دسترسی اجرا:

```bash
chmod +x setdns.sh
```

### 3. اجرای اسکریپت با دسترسی sudo:

```bash
sudo ./setdns.sh
```

```bash
bash <(curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/BigPyth0n/Fix-DNS-Leak-With-GPT/main/setdns.sh)
```

---

## 🧪 تست نهایی (اتوماتیک)

در پایان اجرای اسکریپت، تست کامل DNS Leak به‌صورت خودکار انجام شده و نتیجه در ترمینال نمایش داده می‌شود.

اگر نیاز به تست دستی دارید:

🔗 https://dnsleaktest.com → گزینه **Extended Test** را انتخاب کنید.

---

## 📁 آدرس GitHub

- [مشاهده فایل در GitHub](https://github.com/BigPyth0n/Fix-DNS-Leak-With-GPT)
- [لینک مستقیم اسکریپت (Raw)](https://raw.githubusercontent.com/BigPyth0n/Fix-DNS-Leak-With-GPT/main/setdns.sh)
