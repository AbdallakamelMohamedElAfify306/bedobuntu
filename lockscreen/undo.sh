# SPDX-License-Identifier: GPL-3.0-or-later
G=/home/user/.config/gtk-3.0/gtk.css; grep -vE "phosh-home|phosh-overview|phosh-app-grid" $G > $G.new && mv $G.new $G && chown user:user $G && chmod 644 $G && systemctl restart pixel-phosh && for i in $(seq 1 30); do sleep 1; pgrep -x phosh > /dev/null && break; done; sleep 5; pgrep -x phosh > /dev/null && echo UNDONE || echo FAIL-phosh-not-running
