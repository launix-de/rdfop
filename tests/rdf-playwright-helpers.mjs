const S = 'https://launix.de/rdfop/schema#';

function sid(id) {
  return String(id || '').includes(':') ? `<${id}>` : id;
}

function q(id) {
  return String(id).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

export function createHelpers({ page, request, baseURL }) {
  return {
    S,
    id() {
      return `urn:uuid:${crypto.randomUUID()}`;
    },
    sid,
    selector(selectorId, childId) {
      return `${sid(selectorId)} a <${S}ComponentSelector> .\n${sid(selectorId)} <${S}children> ${sid(childId)} .\n${sid(selectorId)} <${S}selectedNode> ${sid(childId)} .`;
    },
    split(splitId, dir, ratio, leftId, rightId) {
      return `${sid(splitId)} a <${S}Split> .\n${sid(splitId)} <${S}splitDirection> ${JSON.stringify(dir)} .\n${sid(splitId)} <${S}splitRatio> ${JSON.stringify(ratio)} .\n${sid(splitId)} <${S}children> ${sid(leftId)} .\n${sid(splitId)} <${S}children> ${sid(rightId)} .\n${sid(leftId)} <${S}order> "1" .\n${sid(rightId)} <${S}order> "2" .`;
    },
    tabGroup(groupId) {
      return `${sid(groupId)} a <${S}TabGroup> .\n${sid(groupId)} <${S}tabDirection> "top" .`;
    },
    tab(groupId, tabId, label, order, childId) {
      return `${sid(groupId)} <${S}children> ${sid(tabId)} .\n${sid(tabId)} a <${S}Tab> .\n${sid(tabId)} <${S}tabLabel> ${JSON.stringify(label)} .\n${sid(tabId)} <${S}order> ${JSON.stringify(order)} .\n${sid(tabId)} <${S}children> ${sid(childId)} .`;
    },
    htmlView(id, html) {
      return `${sid(id)} a <${S}HTMLView> .\n${sid(id)} <${S}html> ${JSON.stringify(html)} .`;
    },
    async insert(ttl) {
      const resp = await request.post(`${baseURL}/rdfop-save`, {
        form: { insert: ttl },
      });
      if (!resp.ok()) throw new Error(`insert failed: ${resp.status()}`);
    },
    async cleanup(id) {
      try {
        await request.post(`${baseURL}/rdfop-delete`, {
          form: { id },
        });
      } catch (e) {
        // Best-effort cleanup after browser-level failures/timeouts.
      }
    },
    async goto(id) {
      await page.goto(`${baseURL}/view/${encodeURIComponent(id)}`);
    },
    byId(id) {
      return page.getByTestId(id);
    },
    tabById(id) {
      return page.getByTestId(`tab:${id}`);
    },
    panelById(id) {
      return page.getByTestId(`panel:${id}`);
    },
    tabLabels(groupId) {
      return this.byId(groupId).locator('.rdfop-tabs__tab .rdfop-textedit');
    },
    tabIds(groupId) {
      return this.byId(groupId).locator('.rdfop-tabs__tab').evaluateAll(nodes =>
        nodes.map(node => node.getAttribute('data-tab-id'))
      );
    },
    async clickTab(tabId) {
      await this.tabById(tabId).click();
    },
    async dragComponent(sourceSelectorId, targetSelectorId, zone = 'center') {
      const source = this.byId(sourceSelectorId).locator('.rdfop-selector__move');
      const target = this.byId(targetSelectorId);
      await source.waitFor({ state: 'attached' });
      await target.waitFor({ state: 'attached' });
      const box = await target.boundingBox();
      if (!box) throw new Error(`missing bounding box for ${targetSelectorId}`);
      let clientX = box.x + box.width / 2;
      let clientY = box.y + box.height / 2;
      if (zone === 'left') clientX = box.x + Math.max(4, box.width * 0.1);
      if (zone === 'right') clientX = box.x + box.width - Math.max(4, box.width * 0.1);
      if (zone === 'top') clientY = box.y + Math.max(4, box.height * 0.1);
      if (zone === 'bottom') clientY = box.y + box.height - Math.max(4, box.height * 0.1);
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await source.dispatchEvent('dragstart', { dataTransfer });
      await target.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await target.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await target.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await source.dispatchEvent('dragend', { dataTransfer });
      await page.waitForTimeout(150);
    },
    async dragComponentViaTab(sourceSelectorId, hoverTabId, targetSelectorId, zone = 'center', hoverMs = 900) {
      const source = this.byId(sourceSelectorId).locator('.rdfop-selector__move');
      const hoverTab = this.tabById(hoverTabId);
      await source.waitFor({ state: 'attached' });
      await hoverTab.waitFor({ state: 'attached' });
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await source.dispatchEvent('dragstart', { dataTransfer });
      await hoverTab.dispatchEvent('dragover', { dataTransfer });
      await page.waitForTimeout(hoverMs);
      const target = this.byId(targetSelectorId);
      await target.waitFor({ state: 'attached' });
      const box = await target.boundingBox();
      if (!box) throw new Error(`missing bounding box for ${targetSelectorId}`);
      let clientX = box.x + box.width / 2;
      let clientY = box.y + box.height / 2;
      if (zone === 'left') clientX = box.x + Math.max(4, box.width * 0.1);
      if (zone === 'right') clientX = box.x + box.width - Math.max(4, box.width * 0.1);
      if (zone === 'top') clientY = box.y + Math.max(4, box.height * 0.1);
      if (zone === 'bottom') clientY = box.y + box.height - Math.max(4, box.height * 0.1);
      await target.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await target.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await target.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await source.dispatchEvent('dragend', { dataTransfer });
      await page.waitForTimeout(200);
    },
    async dragComponentToTabBar(sourceSelectorId, groupId) {
      const source = this.byId(sourceSelectorId).locator('.rdfop-selector__move');
      const bar = this.byId(groupId).locator('.rdfop-tabs__bar');
      await source.waitFor({ state: 'attached' });
      await bar.waitFor({ state: 'attached' });
      const box = await bar.boundingBox();
      if (!box) throw new Error(`missing bounding box for tab bar ${groupId}`);
      const clientX = box.x + box.width - 10;
      const clientY = box.y + box.height / 2;
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await source.dispatchEvent('dragstart', { dataTransfer });
      await bar.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await bar.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await bar.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await source.dispatchEvent('dragend', { dataTransfer });
      await page.waitForTimeout(200);
    },
    async dragComponentToTabHeader(sourceSelectorId, targetTabId) {
      const source = this.byId(sourceSelectorId).locator('.rdfop-selector__move');
      const targetTab = this.tabById(targetTabId);
      await source.waitFor({ state: 'attached' });
      await targetTab.waitFor({ state: 'attached' });
      const box = await targetTab.boundingBox();
      if (!box) throw new Error(`missing bounding box for tab ${targetTabId}`);
      const clientX = box.x + box.width / 2;
      const clientY = box.y + box.height / 2;
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await source.dispatchEvent('dragstart', { dataTransfer });
      await targetTab.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await source.dispatchEvent('dragend', { dataTransfer });
      await page.waitForTimeout(200);
    },
    async dragExternalComponentToTabHeader({ contentId, sourcePayload, targetTabId, side = 'before', tabLabel = '' }) {
      const targetTab = this.tabById(targetTabId);
      await targetTab.waitFor({ state: 'attached' });
      const box = await targetTab.boundingBox();
      if (!box) throw new Error(`missing bounding box for tab ${targetTabId}`);
      const clientX = side === 'after' ? (box.x + box.width - 4) : (box.x + 4);
      const clientY = box.y + box.height / 2;
      const uri = `${baseURL}/view/${encodeURIComponent(contentId)}`;
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await dataTransfer.evaluate((dt, payload) => {
        dt.setData('text/uri-list', payload.uri);
        dt.setData('text/plain', payload.uri);
        dt.setData('application/x-rdfop-kind', 'component');
        if (payload.sourcePayload) {
          dt.setData('application/x-rdfop-source', JSON.stringify(payload.sourcePayload));
        }
        if (payload.tabLabel) {
          dt.setData('application/x-rdfop-tab-label', payload.tabLabel);
        }
      }, { uri, sourcePayload, tabLabel });
      await targetTab.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await page.waitForTimeout(250);
    },
    async dragExternalUrlToPalette(targetSelectorId, url) {
      const target = this.byId(targetSelectorId);
      await target.waitFor({ state: 'attached' });
      const box = await target.boundingBox();
      if (!box) throw new Error(`missing bounding box for ${targetSelectorId}`);
      const clientX = box.x + box.width / 2;
      const clientY = box.y + box.height / 2;
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await dataTransfer.evaluate((dt, payload) => {
        dt.setData('text/uri-list', payload.url);
        dt.setData('text/plain', payload.url);
      }, { url });
      await target.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await target.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await target.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await page.waitForTimeout(250);
    },
    async dragExternalUrlToTabHeader(targetTabId, url, side = 'before') {
      const targetTab = this.tabById(targetTabId);
      await targetTab.waitFor({ state: 'attached' });
      const box = await targetTab.boundingBox();
      if (!box) throw new Error(`missing bounding box for tab ${targetTabId}`);
      const clientX = side === 'after' ? (box.x + box.width - 4) : (box.x + 4);
      const clientY = box.y + box.height / 2;
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await dataTransfer.evaluate((dt, payload) => {
        dt.setData('text/uri-list', payload.url);
        dt.setData('text/plain', payload.url);
      }, { url });
      await targetTab.dispatchEvent('dragenter', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await page.waitForTimeout(1000);
    },
    async reorderTab(dragTabId, targetTabId, side = 'before') {
      const dragTab = this.tabById(dragTabId);
      const targetTab = this.tabById(targetTabId);
      await dragTab.waitFor({ state: 'attached' });
      await targetTab.waitFor({ state: 'attached' });
      const box = await targetTab.boundingBox();
      if (!box) throw new Error(`missing bounding box for tab ${targetTabId}`);
      const clientX = side === 'after' ? (box.x + box.width - 4) : (box.x + 4);
      const clientY = box.y + box.height / 2;
      const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
      await dragTab.dispatchEvent('dragstart', { dataTransfer });
      await targetTab.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
      await targetTab.dispatchEvent('drop', { dataTransfer, clientX, clientY });
      await dragTab.dispatchEvent('dragend', { dataTransfer });
      await page.waitForTimeout(200);
    },
    textContent(locator) {
      return locator.evaluateAll(nodes => nodes.map(node => node.textContent?.trim() || ''));
    },
    escapeAttr: q,
  };
}
