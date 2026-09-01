%post --nochroot --erroronfail --log=/tmp/fedora-sl7-personalization.log
/usr/libexec/sl7-apply-personalization /mnt/sysroot /run/sl7-personalization
%end
