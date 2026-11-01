'use strict';
'require form';
'require fs';
'require uci';
'require ui';
'require view';

/*
 * Page for luci-app-ethled. The register semantics live in /usr/sbin/ethled;
 * this view only edits /etc/config/ethled and drives that tool.
 */

async function runEthled(args) {
	let res;

	try {
		res = await fs.exec('/usr/sbin/ethled', args);
	}
	catch (err) {
		return _('执行失败') + ': ' + (err?.message ?? String(err));
	}

	if (typeof res === 'string')
		return res;

	let text = [res?.stdout, res?.stderr]
		.filter(s => s != null && s !== '')
		.join('\n');

	return text !== '' ? text : (res?.code === 0 ? _('已完成') : _('退出码 %d').format(res?.code ?? -1));
}

return view.extend({
	load: function() {
		return uci.load('ethled');
	},

	render: function() {
		let m = new form.Map('ethled',
			_('网口指示灯'),
			_('CLX S20P 的网口灯由两类芯片驱动：LAN6 与 2.5G WAN 是 RTL8221B PHY，LAN1-LAN5 是 MT7531AE 交换芯片的内部 PHY。本页配置并写入各自的 LED 寄存器。'));

		let s1 = m.section(form.NamedSection, 'global', 'global', _('全局设置'));
		s1.tabular = true;

		let o = s1.option(form.Flag, 'enabled', _('启用指示灯控制'));
		o.description = _('关闭后本工具不写任何寄存器，网口灯完全交回硬件默认状态。');

		o = s1.option(form.Flag, 'apply_on_link', _('链路恢复后重新下发'));
		o.description = _('接口 ifup 时再写一次，防止驱动或 PHY 复位把设置覆盖回默认值。');

		o = s1.option(form.Flag, 'switch_lan', _('同时控制 LAN1-LAN5'));
		o.description = _('默认关闭。本机 LAN1-LAN5 的灯由 MT7531 硬件默认值驱动，工作正常；' +
			('开启后会按下面各端口的寄存器值写入。改动前建议先点「读取寄存器」记下当前值。'));

		let s2 = m.section(form.TypedSection, 'port', _('端口'));
		s2.tabular = true;
		s2.addremove = false;
		s2.anonymous = false;

		o = s2.option(form.Value, 'label', _('显示名称'));

		o = s2.option(form.ListValue, 'type', _('芯片类型'));
		o.value('rtl8221b', _('RTL8221B（2.5G PHY）'));
		o.value('mt7531', _('MT7531（交换芯片内部 PHY）'));

		o = s2.option(form.Value, 'bus', _('MDIO 总线'));
		o.description = _('在设备上执行 <code>mdio</code> 可列出总线名。');

		o = s2.option(form.Value, 'phy', _('PHY 地址'));
		o.validate = (v) => /^\d{1,2}$/.test(v) ? true : _('请输入十进制 PHY 地址');

		o = s2.option(form.Flag, 'enabled', _('本端口参与下发'));
		o.description = _('关闭时本端口完全不动，保持当前灯光。要临时熄灭请用下面的「全部关灯」。');

		/* RTL8221B: three LEDs, each with its own link-select register. */
		for (const led of [ 0, 1, 2 ]) {
			o = s2.option(form.Flag, 'led%d_enable'.format(led), _('LED%d 点亮').format(led));
			o.depends('type', 'rtl8221b');
			o.description = _('关闭等价于内核驱动的 LED_OFF：link-select 写 0，并清掉 activity 与 polarity 位。');

			o = s2.option(form.Value, 'led%d_speeds'.format(led), _('LED%d 点亮的速率').format(led));
			o.depends('type', 'rtl8221b');
			o.default = '10 100 1000 2500';
			o.validate = (v) => /^(10|100|1000|2500)( +(10|100|1000|2500))*$/.test(v.trim())
				? true : _('用空格分隔，取值只能是 10、100、1000、2500');
			o.description = _('例如 <code>1000 2500</code> 表示只在千兆或 2.5G 链路时点亮。');

			o = s2.option(form.Flag, 'led%d_blink'.format(led), _('LED%d 随流量闪烁').format(led));
			o.depends('type', 'rtl8221b');

			o = s2.option(form.Flag, 'led%d_invert'.format(led), _('LED%d 极性反转').format(led));
			o.depends('type', 'rtl8221b');
			o.description = _('对应 polarity 寄存器位；灯不是低电平驱动时保持关闭。');
		}

		/* MT7531: two LEDs, each configured by an ON and a BLINK register. */
		for (const led of [ 0, 1 ]) {
			o = s2.option(form.Flag, 'led%d'.format(led), _('LED%d 点亮').format(led));
			o.depends('type', 'mt7531');
			o.description = _('关闭时写 <code>0x8000</code> 与 <code>0x0000</code>，即树内设备 DTS 表示「此灯不亮」的值。');

			o = s2.option(form.Value, 'led%d_on_ctrl'.format(led), _('LED%d ON 控制 (0x%x)').format(led, 0x24 + led * 2));
			o.depends('type', 'mt7531');
			o.validate = (v) => /^0x[0-9a-fA-F]{1,4}$/.test(v.trim())
				? true : _('请输入形如 0xc001 的十六进制值');

			o = s2.option(form.Value, 'led%d_blink_ctrl'.format(led), _('LED%d BLINK 控制 (0x%x)').format(led, 0x25 + led * 2));
			o.depends('type', 'mt7531');
			o.validate = (v) => /^0x[0-9a-fA-F]{1,4}$/.test(v.trim())
				? true : _('请输入形如 0x0003 的十六进制值');
		}

		/* Actions on the live registers, independent of the saved settings. */
		let s3 = m.section(form.AbstractSection, 'actions', _('操作与状态'));
		s3.anonymous = true;

		s3.render = function() {
			let out = E('pre', { 'class': 'hidden', 'style': 'white-space:pre-wrap' }, '');

			function addLabel(label, args) {
				let btn = E('button', {
					'class': 'cbi-button',
					'click': async (ev) => {
						ev.target.disabled = true;
						ev.target.textContent = _('处理中…');
						out.textContent = await runEthled(args);
						out.classList.remove('hidden');
						ev.target.disabled = false;
						ev.target.textContent = label;
					}
				}, label);

				return btn;
			}

			return E('div', [
				E('div', { 'class': 'small' },
					_('「立即下发」按已保存的配置写寄存器；「全部关灯」只临时熄灭，重启后仍按配置点亮。保存本页设置请用下方的「保存并应用」。')),
				E('div', { 'style': 'margin:.5em 0' }, [
					addLabel(_('立即下发'), [ 'apply' ]),
					addLabel(_('全部关灯'), [ 'off' ]),
					addLabel(_('按配置恢复'), [ 'on' ]),
					addLabel(_('读取寄存器'), [ 'dump' ]),
					addLabel(_('列出端口'), [ 'ports' ])
				]),
				out
			]);
		};

		return m.render();
	}
});
