# Fix-DNS-Leak-With-GPT
سلام الیسا من چطور میتونم با استفاده از دستور resolvconf  در اوبنتو 20 کلا مسله dns leak رو حل کنم و سرورم که توی ترکیه هست وقتی تست dns leak میزنم فقط ترکیه رو نمایش بده؟
سلام! برای رفع مشکل DNS leak در اوبونتو 20 و اطمینان از اینکه سرور DNS شما فقط سرور ترکیه‌ای را نمایش دهد، می‌توانید از دستور resolvconf استفاده کنید. این دستورات را دنبال کنید:

نصب و تنظیم resolvconf:
ابتدا مطمئن شوید که بسته resolvconf نصب شده است:

bash
Copy code
sudo apt update
sudo apt install resolvconf
پیکربندی فایل /etc/resolv.conf:
فایل /etc/resolv.conf را باز کنید:

bash
Copy code
sudo nano /etc/resolv.conf
محتویات آن را به سرور DNS ترکیه‌ای تغییر دهید. به عنوان مثال:

plaintext
Copy code
nameserver 1.1.1.1  # آدرس IP سرور DNS ترکیه‌ای را در اینجا وارد کنید
nameserver 1.0.0.1  # یک سرور DNS دیگر به عنوان پشتیبان
nameserver 1.1.1.1 
nameserver 1.0.0.1
تنظیم فایل پیکربندی برای resolvconf:
فایل /etc/resolvconf/resolv.conf.d/base را ویرایش کنید:

bash
Copy code
sudo nano /etc/resolvconf/resolv.conf.d/base
آدرس‌های DNS سرور ترکیه‌ای را اضافه کنید:

plaintext
Copy code
nameserver 1.1.1.1  # آدرس IP سرور DNS ترکیه‌ای را در اینجا وارد کنید
nameserver 1.0.0.1  # یک سرور DNS دیگر به عنوان پشتیبان
به‌روزرسانی تنظیمات resolvconf:
پس از تنظیم فایل‌های پیکربندی، دستور زیر را اجرا کنید تا تنظیمات جدید اعمال شود:

bash
Copy code
sudo resolvconf -u
راه‌اندازی مجدد سرویس‌های شبکه:
((((((
برای رفع خطای 
sudo resolvconf -u
sudo: unable to resolve host zdlfyzsx.vm: Name or service not known
===>
sudo nano /etc/hosts
اضافه کردن این سرها
127.0.0.1   localhost
127.0.1.1   zdlfyzsx.vm

))))))
برای اطمینان از اعمال تغییرات، سرویس‌های شبکه را مجدداً راه‌اندازی کنید:

bash
Copy code
sudo systemctl restart networking
بعد از این مراحل، باید تنها سرور DNS ترکیه‌ای مورد استفاده قرار گیرد. برای تست این تنظیمات، از وب‌سایت‌هایی مانند DNS Leak Test استفاده کنید تا مطمئن شوید که فقط سرور ترکیه‌ای را نمایش می‌دهند.

ایم خطا رو داد
Failed to restart networking.service: Unit networking.service not found.
ChatGPT
در اوبونتو 20، سرویس networking به طور پیش‌فرض نصب نیست. به جای آن از systemd-resolved برای مدیریت تنظیمات شبکه استفاده می‌شود. در اینجا نحوه استفاده از systemd-resolved برای پیکربندی DNS آورده شده است:

نصب و تنظیم resolvconf:
اگر قبلاً نصب نشده، resolvconf را نصب کنید:

bash
Copy code
sudo apt update
sudo apt install resolvconf
پیکربندی فایل /etc/resolv.conf:
فایل /etc/resolv.conf را باز کنید:

bash
Copy code
sudo nano /etc/resolv.conf
محتویات آن را به سرور DNS ترکیه‌ای تغییر دهید. به عنوان مثال:

plaintext
Copy code
nameserver 1.1.1.1  # آدرس IP سرور DNS ترکیه‌ای را در اینجا وارد کنید
nameserver 1.0.0.1  # یک سرور DNS دیگر به عنوان پشتیبان
تنظیم فایل پیکربندی برای resolvconf:
فایل /etc/resolvconf/resolv.conf.d/base را ویرایش کنید:

bash
Copy code
sudo nano /etc/resolvconf/resolv.conf.d/base
آدرس‌های DNS سرور ترکیه‌ای را اضافه کنید:

plaintext
Copy code
nameserver 1.1.1.1  # آدرس IP سرور DNS ترکیه‌ای را در اینجا وارد کنید
nameserver 1.0.0.1  # یک سرور DNS دیگر به عنوان پشتیبان
به‌روزرسانی تنظیمات resolvconf:
پس از تنظیم فایل‌های پیکربندی، دستور زیر را اجرا کنید تا تنظیمات جدید اعمال شود:

bash
Copy code
sudo resolvconf -u
پیکربندی systemd-resolved:
فایل /etc/systemd/resolved.conf را ویرایش کنید:

bash
Copy code
sudo nano /etc/systemd/resolved.conf
خط زیر را پیدا کنید و تنظیمات را به این صورت تغییر دهید:

plaintext
Copy code
#DNS=
آن را به این صورت تغییر دهید:

plaintext
Copy code
DNS=1.1.1.1 1.0.0.1  # آدرس IP سرورهای DNS ترکیه‌ای را در اینجا وارد کنید
فعال‌سازی و راه‌اندازی مجدد systemd-resolved:
برای اطمینان از اعمال تغییرات، systemd-resolved را فعال و مجدداً راه‌اندازی کنید:

bash
Copy code
sudo systemctl enable systemd-resolved
sudo systemctl restart systemd-resolved
ایجاد لینک نمادین به /etc/resolv.conf:
مطمئن شوید که /etc/resolv.conf به /run/systemd/resolve/resolv.conf لینک شده است:

bash
Copy code
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
بعد از انجام این مراحل، تنظیمات DNS شما باید فقط از سرورهای DNS ترکیه‌ای استفاده کند. برای تست این تنظیمات، از وب‌سایت‌هایی مانند DNS Leak Test استفاده کنید تا مطمئن شوید که فقط سرور ترکیه‌ای را نمایش می‌دهند.
