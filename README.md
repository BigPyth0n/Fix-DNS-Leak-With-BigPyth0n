# 🛡️ Fix DNS Leak Test Script (برای اوبونتو)

این اسکریپت `setdns.sh` برای رفع مشکل **DNS Leak** در اوبونتو 20.04 و بالاتر طراحی شده است.  
هدف آن استفاده‌ی کامل از **Cloudflare DNS over HTTPS (DoH)** از طریق سرویس `cloudflared` است تا هیچ درخواست DNS به بیرون نشت نکند.  

---

## 🎯 قابلیت‌های اسکریپت

✅ به‌روزرسانی کامل و ارتقای سیستم (`upgrade + dist-upgrade`)  
✅ نصب ابزارهای ضروری + `nano` و `tmux`  
✅ نصب و پیکربندی سرویس رسمی `cloudflared`  
✅ تنظیم `systemd-resolved` برای هدایت همه درخواست‌ها به 127.0.0.1  
✅ تصحیح خودکار `/etc/resolv.conf`  
✅ تست خودکار پس از نصب (اطمینان از فعال بودن cloudflared روی پورت 53)  
✅ جلوگیری کامل از نشتی DNS (DNS Leak)  

---

## ⚠️ نکته مهم

- در این نسخه دیگر از `resolvconf` استفاده نمی‌شود (حتی در صورت نصب، حذف خواهد شد).  
- کل سیستم شما در طول اجرا به آخرین نسخه‌های پایدار ارتقا داده می‌شود.  
- پس از پایان نصب می‌توانید نتیجه را با **Extended Test** در [dnsleaktest.com](https://dnsleaktest.com) بررسی کنید.  

---

## ⚙️ پیش‌نیازها

- Ubuntu 20.04 یا بالاتر  
- دسترسی `sudo`  
- اتصال اینترنت  

---

## 🚀 دانلود و اجرای مستقیم از GitHub

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

### 🚀 اجرای مستقیم با curl:
```bash
bash <(curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/BigPyth0n/Fix-DNS-Leak-With-GPT/main/setdns.sh)
```

---

## 🧪 تست نهایی (دستی)

اسکریپت به‌صورت خودکار تست اولیه انجام می‌دهد.  
برای تست دستی و سریع می‌توانید دستورات زیر را بعد از اتمام نصب اجرا کنید:

```bash
# چک کن resolv.conf به systemd-resolved لینک شده باشد
readlink -f /etc/resolv.conf    # باید باشد: /run/systemd/resolve/resolv.conf

# مطمئن شو cloudflared روی پورت 53 فعال است
ss -tulnp | grep '127.0.0.1:53'

# تست رزولوشن مستقیم از cloudflared
dig +short @127.0.0.1 google.com

# تست رزولوشن از مسیر سیستم
dig +short google.com
```

## 🧪 تست نهایی (به صورت اسکریپتی)

اسکریپت به‌صورت خودکار تست اولیه انجام می‌دهد.  


```bash
# چک کن resolv.conf به systemd-resolved لینک شده باشد
bash <(curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/BigPyth0n/Fix-DNS-Leak-With-BigPyth0n/refs/heads/main/TestFixed.sh)
```

---

و در نهایت برای اطمینان نهایی:  
🔗 [dnsleaktest.com](https://dnsleaktest.com) → گزینه **Extended Test** را انتخاب کنید.  

---

## 📁 آدرس GitHub

- [مشاهده فایل در GitHub](https://github.com/BigPyth0n/Fix-DNS-Leak-With-GPT)  
- [لینک مستقیم اسکریپت (Raw)](https://raw.githubusercontent.com/BigPyth0n/Fix-DNS-Leak-With-GPT/main/setdns.sh)  
