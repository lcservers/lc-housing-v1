document.querySelectorAll('.systemCard').forEach((card) => card.remove());
const app = document.getElementById('app');
const list = document.getElementById('houseList');
const map = document.getElementById('map');
const form = document.getElementById('houseForm');
const message = document.getElementById('message');
const imagePreview = document.getElementById('imagePreview');
const adminShell = document.getElementById('adminShell');
const listingShell = document.getElementById('listingShell');
const listingMessage = document.getElementById('listingMessage');
let listingHouse = null;
let ownerMenuContext = { isInsideProperty: false, propertyType: 'shell' };

let houses = [];
let selected = null;
let config = {};
let polyzone = [];
let doorLocks = [];
let pendingCreateAfterPoly = false;
let pendingDeleteName = null;
let deletingProperty = false;
let pendingBuyName = null;
let buyingProperty = false;
let pendingSellName = null;
let sellingProperty = false;
let currentLocation = null;
let shellPreviewRequest = null;

const shellPreviewCacheKey = 'lcHousingShellPreviewsV7';

function shellModels() {
    return (config.shells || []).map((shell) => typeof shell === 'string' ? shell : shell.model).filter(Boolean);
}

function shellInfo(model, index = 0) {
    const configured = (config.shells || []).find((shell) => typeof shell === 'object' && shell.model === model) || {};
    return {
        model,
        tier: Number(configured.tier || index + 1),
        name: configured.label || model.replace(/^shell_/, '').replace(/_/g, ' '),
        description: configured.description || 'Housing shell interior'
    };
}

function readShellPreviewCache() {
    try { return JSON.parse(localStorage.getItem(shellPreviewCacheKey) || '{}'); }
    catch (_) { return {}; }
}

function cachedShellPreview(model) {
    return readShellPreviewCache()[model] || '';
}

function cacheShellPreview(model, image) {
    if (!model || !image) return;
    try {
        const cache = readShellPreviewCache();
        cache[model] = image;
        localStorage.setItem(shellPreviewCacheKey, JSON.stringify(cache));
    } catch (_) { /* Keep the current preview even if Chromium storage is full. */ }
}

function cleanPropertyName(value) {
    return String(value || "")
        .toLowerCase()
        .split("")
        .map((char) => /[a-z0-9_#-]/.test(char) ? char : (/\s/.test(char) ? "_" : ""))
        .join("")
        .replace(/_+/g, "_")
        .replace(/^_+|_+$/g, "")
        .slice(0, 64);
}

function nextPropertyNumber() {
    return Math.max(1, houses.length + 1);
}

function numberedPropertyName(value) {
    const suffix = "_#" + nextPropertyNumber();
    const base = cleanPropertyName(value).replace(/_#?\d+$/, "") || "house";
    return base.slice(0, 64 - suffix.length) + suffix;
}

function applyCurrentLocation(coords, forceName = false) {
    if (!coords) return;
    currentLocation = coords;
    fields.x.value = coords.x;
    fields.y.value = coords.y;
    fields.z.value = coords.z;
    fields.h.value = coords.h;

    if (!selected && coords.label && (forceName || !fields.label.value.trim())) {
        fields.label.value = coords.label;
    }

    if (!selected && coords.label && (forceName || !fields.customName.value.trim())) {
        fields.customName.value = coords.name || numberedPropertyName(coords.nameBase || coords.label);
    }
}

const fields = {
    name: document.getElementById('name'),
    customName: document.getElementById('customName'),
    label: document.getElementById('label'),
    price: document.getElementById('price'),
    tier: document.getElementById('tier'),
    propertyType: document.getElementById('propertyType'),
    shell: document.getElementById('shell'),
    ipl: document.getElementById('ipl'),
    mlo: document.getElementById('mlo'),
    x: document.getElementById('x'),
    y: document.getElementById('y'),
    z: document.getElementById('z'),
    h: document.getElementById('h'),
    image: document.getElementById('image'),
    garageEnabled: document.getElementById('garageEnabled'),
    garageX: document.getElementById('garageX'),
    garageY: document.getElementById('garageY'),
    garageZ: document.getElementById('garageZ'),
    garageW: document.getElementById('garageW')
};

function post(name, data = {}) {
    const timeout = new Promise((_, reject) => {
        setTimeout(() => reject(new Error(`${name} timed out.`)), 10000);
    });
    const request = fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then(async (response) => {
        const text = await response.text();
        return text ? JSON.parse(text) : { ok: true };
    });
    return Promise.race([request, timeout]);
}

function setMessage(text, type = '') {
    message.textContent = text || '';
    message.className = `message ${type}`;
}



function setListingMessage(text, type = '') {
    listingMessage.textContent = text || '';
    listingMessage.className = `message ${type}`;
}

function toggleDeleteConfirm(show) {
    document.getElementById('deleteConfirm').classList.toggle('hiddenGroup', !show);
}

function toggleBuyConfirm(show) {
    document.getElementById('buyConfirm').classList.toggle('hiddenGroup', !show);
}

function toggleSellConfirm(show) {
    document.getElementById('sellConfirm').classList.toggle('hiddenGroup', !show);
}


function garageSupported() {
    return Boolean(config.garage && config.garage.enabled);
}

function updateGarageVisibility() {
    const supported = garageSupported();
    const enabled = supported && fields.garageEnabled.checked;
    const garageToggle = fields.garageEnabled.closest('label');
    const garageFields = document.getElementById('garageFields');

    if (garageToggle) garageToggle.classList.toggle('hiddenGroup', !supported);
    garageFields.classList.toggle('hiddenGroup', !supported);
    garageFields.classList.toggle('disabled', !enabled);

    fields.garageEnabled.disabled = !supported;
    fields.garageX.disabled = !enabled;
    fields.garageY.disabled = !enabled;
    fields.garageZ.disabled = !enabled;
    fields.garageW.disabled = !enabled;
    document.getElementById('garageBtn').disabled = !supported;

    if (!supported) {
        fields.garageEnabled.checked = false;
        fields.garageX.value = '';
        fields.garageY.value = '';
        fields.garageZ.value = '';
        fields.garageW.value = '';
    }
}

function showAdminPanel() {
    adminShell.classList.remove('hiddenGroup');
    listingShell.classList.add('hiddenGroup');
}

function updateListingHouseFromResult(result) {
    if (result && result.houses) replaceHouses(result.houses);
    if (!listingHouse) return;
    const nextHouse = houses.find((house) => house.name === listingHouse.name);
    if (nextHouse) showListingPanel(nextHouse);
}

function closePanel() {
    app.classList.add('hidden');
    listingHouse = null;
    post('close');
}

function ownerPost(action, payload, successText) {
    if (!listingHouse) return Promise.resolve();
    setListingMessage('Saving...');
    return post(action, payload).then((result) => {
        if (result.ok) {
            updateListingHouseFromResult(result);
            setListingMessage(successText, 'success');
        } else {
            setListingMessage(result.message || 'Action failed.', 'error');
        }
        return result;
    });
}

function showListingPanel(house) {
    listingHouse = house;
    pendingBuyName = null;
    pendingSellName = null;
    toggleBuyConfirm(false);
    toggleSellConfirm(false);
    adminShell.classList.add('hiddenGroup');
    listingShell.classList.remove('hiddenGroup');
    document.getElementById('listingTitle').textContent = house.label || 'Property Listing';
    document.getElementById('listingSubtitle').textContent = house.isOwner ? 'Owned property management' : (house.owned ? 'This property is already owned' : 'Available for purchase');
    document.getElementById('listingPrice').textContent = money(house.price || 0);
    const listingType = (house.propertyType || 'shell').toLowerCase();
    const isShellListing = listingType === 'shell';
    const isMloProperty = listingType === 'mlo' || listingType === 'ipl';
    const isInsideProperty = Boolean(ownerMenuContext.isInsideProperty);
    document.getElementById('listingType').textContent = listingType.toUpperCase();
    document.getElementById('listingStatus').textContent = house.isOwner || house.owned ? 'Owned' : 'For Sale';
    document.getElementById('listingAddress').textContent = house.label || 'Unknown';
    document.getElementById('listingName').textContent = house.name || 'unknown';
    const tierRow = document.getElementById('listingTier').closest('div');
    if (tierRow) tierRow.classList.toggle('hiddenGroup', !isShellListing || Boolean(house.isOwner));
    document.getElementById('listingTier').textContent = String(house.tier || 1);
    document.getElementById('buyerActions').classList.toggle('hiddenGroup', Boolean(house.isOwner));
    document.getElementById('ownerActions').classList.toggle('hiddenGroup', !house.isOwner);
    const listingDetails = document.querySelector('.listingDetails');
    if (listingDetails) {
        listingDetails.classList.toggle('ownerModernLayout', Boolean(house.isOwner));
        listingDetails.classList.toggle('ownerShellLayout', Boolean(house.isOwner && isShellListing));
    }
    const securitySection = document.getElementById('ownerSecurityActions');
    if (securitySection) securitySection.classList.toggle('hiddenGroup', !isMloProperty);
    const canPreview = !house.owned && !house.isOwner && isShellListing;
    const previewBtn = document.getElementById('previewBtn');
    previewBtn.classList.toggle('hiddenGroup', !canPreview);
    previewBtn.disabled = !canPreview;
    document.getElementById('buyBtn').disabled = Boolean(house.owned);
    document.getElementById('buyBtn').textContent = house.owned ? 'Already Owned' : 'Buy Property';

    document.getElementById('ownerTypeLabel').textContent = isMloProperty ? (listingType === 'ipl' ? 'IPL Property' : 'MLO Property') : 'Shell Property';
    document.getElementById('ownerContextNote').textContent = isMloProperty
        ? (isInsideProperty ? 'You are inside the property zone. Interior locations can be updated here.' : 'Walk inside the MLO to set interior locations. Enter through the physical doors.')
        : (isInsideProperty ? 'You are inside this shell. Interior locations are available.' : 'Walk to the entrance to enter. Interior setup unlocks while you are inside.');

    const lockBtn = document.getElementById('lockBtn');
    const locked = Boolean(house.settings && house.settings.locked);
    document.getElementById('listingLock').textContent = locked ? 'Locked' : 'Unlocked';
    lockBtn.textContent = locked ? (isMloProperty ? 'Unlock All Doors' : 'Unlock Door') : (isMloProperty ? 'Lock All Doors' : 'Lock Door');
    lockBtn.classList.toggle('locked', locked);
    lockBtn.classList.toggle('unlocked', !locked);

    const addDoorBtn = document.getElementById('addDoorBtn');
    addDoorBtn.disabled = !isMloProperty;
    addDoorBtn.title = isMloProperty ? 'Stand near and face the MLO door you want to add.' : 'Custom door locks are only available for MLO/IPL properties.';
    document.getElementById('securityHint').textContent = isMloProperty
        ? 'Stand close to an MLO door or garage door before choosing Add MLO Lock.'
        : 'Shell entrance locking is built in. Extra MLO locks are not needed.';

    const setExitBtn = document.getElementById('setExitBtn');
    setExitBtn.classList.toggle('hiddenGroup', isMloProperty);
    setExitBtn.disabled = isMloProperty || !isInsideProperty;
    ['setStashBtn', 'setWardrobeBtn', 'setLogoutBtn'].forEach((id) => {
        document.getElementById(id).disabled = !isInsideProperty;
    });
    const decorateBtn = document.getElementById('decorateBtn');
    decorateBtn.classList.toggle('hiddenGroup', listingType === 'ipl');
    decorateBtn.disabled = !isInsideProperty || listingType === 'ipl';
    document.getElementById('interiorHint').textContent = isInsideProperty
        ? 'Ready — move to the exact spot you want to save.'
        : (isMloProperty ? 'Unavailable outside: walk inside the saved property polyzone first.' : 'Unavailable outside: enter the shell from its front door first.');
    document.getElementById('ownerInteriorActions').classList.toggle('ownerActionUnavailable', !isInsideProperty);

    renderOwnerDoorList(house);
    setListingMessage('');
}

function money(value) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value || 0);
}

function toPercent(house) {
    const bounds = config.bounds || { minX: -4200, maxX: 4500, minY: -4300, maxY: 8400 };
    const x = ((house.x - bounds.minX) / (bounds.maxX - bounds.minX)) * 100;
    const y = 100 - (((house.y - bounds.minY) / (bounds.maxY - bounds.minY)) * 100);
    return { x: Math.max(1, Math.min(99, x)), y: Math.max(1, Math.min(99, y)) };
}

function payload() {
    const propertyType = fields.propertyType.value;
    return {
        name: fields.name.value,
        nameBase: currentLocation ? currentLocation.nameBase : "",
        label: fields.label.value.trim(),
        price: Number(fields.price.value),
        tier: propertyType === 'shell' ? Number(fields.tier.value) : 1,
        propertyType,
        shell: propertyType === 'shell' ? fields.shell.value.trim() : '',
        ipl: propertyType === 'ipl' ? fields.ipl.value.trim() : '',
        mlo: propertyType === 'mlo' ? fields.mlo.value.trim() : '',
        x: Number(fields.x.value),
        y: Number(fields.y.value),
        z: Number(fields.z.value),
        h: Number(fields.h.value || 0),
        image: fields.image.value.trim(),
        polyzone,
        doorLocks,
        garageEnabled: garageSupported() && fields.garageEnabled.checked,
        garageX: garageSupported() ? Number(fields.garageX.value || 0) : 0,
        garageY: garageSupported() ? Number(fields.garageY.value || 0) : 0,
        garageZ: garageSupported() ? Number(fields.garageZ.value || 0) : 0,
        garageW: garageSupported() ? Number(fields.garageW.value || 0) : 0
    };
}

function renderImage(url) {
    if (!imagePreview) return;
    imagePreview.classList.toggle('hasImage', Boolean(url));
    if (url) {
        imagePreview.style.backgroundImage = `url("${url.replace(/"/g, '%22')}")`;
        imagePreview.innerHTML = '';
    } else {
        imagePreview.style.backgroundImage = '';
        imagePreview.innerHTML = '<span>No image saved</span>';
    }
}

function updateTypeGroups() {
    const type = fields.propertyType.value;
    const isShell = type === 'shell';
    document.getElementById('shellGroup').classList.toggle('hiddenGroup', !isShell);
    document.getElementById('mloGroup').classList.toggle('hiddenGroup', type !== 'mlo');
    document.getElementById('iplGroup').classList.toggle('hiddenGroup', type !== 'ipl');
    const doorLockFields = document.getElementById('doorLockFields');
    if (doorLockFields) doorLockFields.classList.toggle('hiddenGroup', isShell);
}

function updatePolyCount() {
    document.getElementById('polyCount').textContent = `${polyzone.length} point${polyzone.length === 1 ? '' : 's'}`;
}

function updateDoorCount() {
    const count = document.getElementById("doorCount");
    if (count) count.textContent = String(doorLocks.length) + " door" + (doorLocks.length === 1 ? "" : "s");
    renderAdminDoorList();
}

function escapeHtml(value) {
    return String(value || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function houseDoors(house) {
    return house && house.settings && Array.isArray(house.settings.doors) ? [...house.settings.doors] : [];
}

function doorCoordsText(door) {
    const c = door && door.coords ? door.coords : {};
    return "X: " + Number(c.x || 0).toFixed(2) + ", Y: " + Number(c.y || 0).toFixed(2) + ", Z: " + Number(c.z || 0).toFixed(2);
}

function renderDoorList(containerId, doors, emptyText, options = {}) {
    const container = document.getElementById(containerId);
    if (!container) return;

    if (!doors || doors.length < 1) {
        container.innerHTML = "<div class=\"doorEmpty\">" + emptyText + "</div>";
        return;
    }

    const showTeleport = options.showTeleport !== false;
    container.innerHTML = doors.map((door, index) => {
        const label = escapeHtml(door.name || ("Door " + (index + 1)));
        const type = escapeHtml(door.doorType || "single");
        const panel = door.panel ? " / " + escapeHtml(door.panel) : "";
        const teleportButton = showTeleport ? "<button type=\"button\" data-action=\"teleport\">TP</button>" : "";
        return "<article class=\"doorItem\" data-index=\"" + index + "\">" +
            "<div><strong>" + label + "</strong><span>" + type + panel + "</span><small>" + doorCoordsText(door) + "</small></div>" +
            "<div class=\"doorActions\">" + teleportButton + "<button type=\"button\" data-action=\"edit\">Edit</button><button type=\"button\" data-action=\"remove\">Remove</button></div>" +
            "</article>";
    }).join("");
}

function renderAdminDoorList() {
    renderDoorList("adminDoorList", doorLocks, "No doors saved for this property.");
}

function renderOwnerDoorList(house) {
    const section = document.getElementById("ownerDoorSection");
    const count = document.getElementById("ownerDoorCount");
    const doors = houseDoors(house);
    const propertyType = String(house && house.propertyType || 'shell').toLowerCase();
    const supportsCustomDoors = propertyType === 'mlo' || propertyType === 'ipl';

    if (section) section.classList.toggle("hiddenGroup", !house || !house.isOwner || !supportsCustomDoors);
    if (count) count.textContent = String(doors.length) + " door" + (doors.length === 1 ? "" : "s");
    renderDoorList("ownerDoorList", doors, "No MLO locks saved yet. Stand near a door and choose Add MLO Lock.", { showTeleport: false });
}

function setMode(house) {
    selected = house || null;
    toggleDeleteConfirm(false);
    document.getElementById('saveBtn').textContent = selected ? 'Save Changes' : 'Create Property';
    document.getElementById('deleteBtn').style.display = selected ? 'inline-block' : 'none';
    document.getElementById('deleteTopBtn').style.display = selected ? 'inline-block' : 'none';
    fields.customName.disabled = Boolean(selected);
    fields.propertyType.disabled = Boolean(selected);
}

function displayShellPreview(model, image = '') {
    const models = shellModels();
    const index = Math.max(0, models.indexOf(model));
    const info = shellInfo(model, index);
    const preview = document.getElementById('shellPreview');
    document.getElementById('shellPreviewTier').textContent = `Tier ${info.tier}`;
    document.getElementById('shellPreviewName').textContent = info.name;
    document.getElementById('shellPreviewModel').textContent = info.model;
    preview.classList.toggle('hasImage', Boolean(image));
    preview.style.backgroundImage = image ? `url("${image.replace(/"/g, '%22')}")` : '';
    document.getElementById('shellPreviewStatus').textContent = image ? 'Live preview cached' : 'Select to preview';
}

function updateShellChoices() {
    document.querySelectorAll('.shellChoice').forEach((button) => {
        const active = button.dataset.shell === fields.shell.value;
        button.classList.toggle('active', active);
        button.disabled = Boolean(selected);
        button.setAttribute('aria-checked', active ? 'true' : 'false');
    });
}

async function requestShellPreview(model) {
    if (!model || shellPreviewRequest) return;
    const cached = cachedShellPreview(model);
    if (cached) {
        displayShellPreview(model, cached);
        return;
    }
    shellPreviewRequest = model;
    document.getElementById('shellPreviewLoading').classList.remove('hiddenGroup');
    document.getElementById('shellPreviewStatus').textContent = 'Rendering…';
    try {
        const result = await post('previewAdminShell', { shell: model });
        if (!result.ok) throw new Error(result.message || 'Preview could not start.');
    } catch (error) {
        shellPreviewRequest = null;
        document.getElementById('shellPreviewLoading').classList.add('hiddenGroup');
        document.getElementById('shellPreviewStatus').textContent = 'Preview unavailable';
        setMessage(error.message || 'Shell preview failed.', 'error');
    }
}

function selectShell(model, capture = true) {
    const models = shellModels();
    if (!models.includes(model)) return;
    const index = models.indexOf(model);
    fields.shell.value = model;
    fields.tier.value = String(shellInfo(model, index).tier);
    updateShellChoices();
    const cached = cachedShellPreview(model);
    displayShellPreview(model, cached);
    if (capture && !cached) requestShellPreview(model);
}

function fillShellOptions() {
    const picker = document.getElementById('shellPicker');
    picker.innerHTML = '';
    shellModels().forEach((model, index) => {
        const info = shellInfo(model, index);
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'shellChoice';
        button.dataset.shell = model;
        button.setAttribute('role', 'radio');
        button.innerHTML = `<span class="shellChoiceIndex">${info.tier}</span><span><strong>${escapeHtml(info.name)}</strong><small>${escapeHtml(info.description)}</small></span>`;
        button.addEventListener('click', () => selectShell(model, true));
        picker.appendChild(button);
    });
    updateShellChoices();
}

function fillForm(house) {
    const defaults = config.defaults || { price: 250000, tier: 1, type: 'shell', shell: 'shell_v16low', image: '' };
    const garage = garageSupported() && house && house.garage ? house.garage : {};
    const hasGarage = garageSupported() && Boolean(Number(garage.x) || Number(garage.y) || Number(garage.z));

    setMode(house);
    fields.name.value = house ? house.name : '';
    fields.customName.value = '';
    fields.label.value = house ? house.label : '';
    fields.price.value = house ? house.price : defaults.price;
    fields.tier.value = house ? house.tier : defaults.tier;
    fields.propertyType.value = house ? (house.propertyType || 'shell') : (defaults.type || 'shell');
    fields.shell.value = house ? (house.shell || '') : (defaults.shell || 'shell_v16low');
    fields.ipl.value = house ? (house.ipl || '') : (defaults.ipl || '');
    fields.mlo.value = house ? (house.mlo || '') : (defaults.mlo || '');
    fields.x.value = house ? house.x : '';
    fields.y.value = house ? house.y : '';
    fields.z.value = house ? house.z : '';
    fields.h.value = house ? house.h : '';
    fields.image.value = house ? house.image : defaults.image;
    fields.garageEnabled.checked = hasGarage;
    fields.garageX.value = hasGarage ? garage.x : '';
    fields.garageY.value = hasGarage ? garage.y : '';
    fields.garageZ.value = hasGarage ? garage.z : '';
    fields.garageW.value = hasGarage ? (garage.w || 0) : '';
    polyzone = house && Array.isArray(house.polyzone) ? [...house.polyzone] : [];
    doorLocks = house && house.settings && Array.isArray(house.settings.doors) ? [...house.settings.doors] : [];

    document.getElementById('garageFields').classList.toggle('disabled', !hasGarage);
    const interiorLockNote = document.getElementById('interiorLockNote');
    if (interiorLockNote) interiorLockNote.classList.toggle('hiddenGroup', !house);
    document.getElementById('shellGroup').classList.toggle('lockedInterior', Boolean(house));
    document.getElementById('mloGroup').classList.toggle('lockedInterior', Boolean(house));
    document.getElementById('iplGroup').classList.toggle('lockedInterior', Boolean(house));
    updateGarageVisibility();
    updateTypeGroups();
    updatePolyCount();
    updateDoorCount();
    renderImage(fields.image.value);
    selectShell(fields.shell.value || shellModels()[0], false);
}

function filteredHouses() {
    const term = document.getElementById('search').value.trim().toLowerCase();
    const status = document.getElementById('statusFilter') ? document.getElementById('statusFilter').value : 'all';
    return houses.filter((house) => {
        const matchesTerm = !term || `${house.label} ${house.name} ${house.propertyType} ${house.owner || ''}`.toLowerCase().includes(term);
        const matchesStatus = status === 'all' || (status === 'owned' && house.owned) || (status === 'listed' && !house.owned);
        return matchesTerm && matchesStatus;
    });
}

function selectHouse(name) {
    const house = houses.find((item) => item.name === name);
    if (!house) return;
    pendingDeleteName = null;
    toggleDeleteConfirm(false);
    fillForm(house);
    render();
}

function renderStats(visible) {
    const owned = houses.filter((house) => house.owned).length;
    const listed = houses.length - owned;
    const totalSales = houses.filter((house) => house.owned).reduce((sum, house) => sum + Number(house.price || 0), 0);
    document.getElementById('totalCount').textContent = String(houses.length);
    document.getElementById('ownedCount').textContent = String(owned);
    document.getElementById('mapCount').textContent = `${visible.length} visible`;
    const saleCount = document.getElementById('saleCount');
    const totalSalesEl = document.getElementById('totalSales');
    if (saleCount) saleCount.textContent = String(listed);
    if (totalSalesEl) totalSalesEl.textContent = money(totalSales);
}

function renderList() {
    const visible = filteredHouses();
    list.innerHTML = '';
    renderStats(visible);

    visible.forEach((house) => {
        const row = document.createElement('tr');
        row.className = selected && selected.name === house.name ? 'active' : '';
        row.innerHTML = `
            <td><div class="propertyCell"><div><strong>${house.label}</strong><span>ID: ${house.name}</span></div></div></td>
            <td><div>${house.label}</div><span class="subtle">X: ${Number(house.x || 0).toFixed(2)}, Y: ${Number(house.y || 0).toFixed(2)}</span></td>
            <td><div>${(house.propertyType || 'shell').toUpperCase()}</div><span class="subtle">Tier ${house.tier || 1}</span></td>
            <td>${money(house.price)}</td>
            <td><span class="status ${house.owned ? 'owned' : 'sale'}">${house.owned ? 'Owned' : 'For Sale'}</span></td>
            <td>${house.owner || '-'}</td>
            <td><div class="rowActions"><button type="button" title="View">View</button><button type="button" title="Edit">Edit</button></div></td>
        `;
        row.addEventListener('click', () => selectHouse(house.name));
        row.querySelectorAll('button').forEach((button) => button.addEventListener('click', (event) => {
            event.stopPropagation();
            selectHouse(house.name);
        }));
        list.appendChild(row);
    });
}

function renderMap() {
    if (!map) return;
    map.querySelectorAll('.dot').forEach((dot) => dot.remove());
    filteredHouses().forEach((house) => {
        const point = toPercent(house);
        const dot = document.createElement('button');
        dot.type = 'button';
        dot.className = `dot ${house.owned ? 'owned' : ''} ${selected && selected.name === house.name ? 'active' : ''}`;
        dot.style.left = `${point.x}%`;
        dot.style.top = `${point.y}%`;
        dot.title = `${house.label} - ${money(house.price)}`;
        dot.addEventListener('click', () => selectHouse(house.name));
        map.appendChild(dot);
    });
}


function render() {
    renderList();
    renderMap();
}

function replaceHouses(nextHouses) {
    houses = Array.isArray(nextHouses) ? nextHouses : [];
    if (selected) selected = houses.find((house) => house.name === selected.name) || null;
    if (selected) fillForm(selected);
    render();
}

function updateDebugControls() {
    const scanDoorsBtn = document.getElementById('scanDoorsBtn');
    const debugEnabled = config.debug === true;
    if (scanDoorsBtn) scanDoorsBtn.classList.toggle('hiddenGroup', !debugEnabled);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') {
        config = data.config || {};
        houses = data.houses || [];
        updateDebugControls();
        fillShellOptions();
        updateGarageVisibility();
        app.classList.remove('hidden');
        showAdminPanel();
        setMessage('');
        fillForm(null);
        if (data.current) applyCurrentLocation(data.current, true);
        render();
    }
    if (data.action === 'openListing') {
        app.classList.remove('hidden');
        ownerMenuContext = data.ownerMenuContext || { isInsideProperty: false, propertyType: (data.house && data.house.propertyType) || 'shell' };
        showListingPanel(data.house || {});
    }
    if (data.action === 'replaceHouses') {
        replaceHouses(data.houses);
        if (listingHouse) {
            const nextHouse = houses.find((house) => house.name === listingHouse.name);
            if (nextHouse) showListingPanel(nextHouse);
        }
    }
    if (data.action === 'hide') app.classList.add('hidden');
    if (data.action === 'show') app.classList.remove('hidden');
    if (data.action === 'shellPreviewReady') {
        shellPreviewRequest = null;
        document.getElementById('shellPreviewLoading').classList.add('hiddenGroup');
        app.classList.remove('hidden');
        showAdminPanel();
        if (data.ok && data.shell && data.image) {
            cacheShellPreview(data.shell, data.image);
            if (fields.shell.value === data.shell) displayShellPreview(data.shell, data.image);
            setMessage('Actual shell interior preview captured.', 'success');
        } else {
            document.getElementById('shellPreviewStatus').textContent = 'Preview unavailable';
            setMessage(data.message || 'Shell preview could not be captured.', 'error');
        }
    }
    if (data.action === 'entranceResult') {
        app.classList.remove('hidden');
        showAdminPanel();
        applyCurrentLocation(data.coords, true);
        setMessage('Entrance saved to the form.', 'success');
        render();
    }
    if (data.action === 'close') app.classList.add('hidden');
    if (data.action === 'doorScanResult') {
        doorLocks = Array.isArray(data.doors) ? data.doors : [];
        app.classList.remove('hidden');
        updateDoorCount();
        if (data.export && data.export.ok) {
            setMessage('Door scan added to the form and written to ' + (data.export.file || 'door_scan_debug.lua') + '.', doorLocks.length ? 'success' : 'error');
        } else {
            setMessage((data.export && data.export.message) || 'Door scan completed, but the debug file was not written.', 'error');
        }
    }
    if (data.action === 'polyResult') {
        polyzone = Array.isArray(data.points) ? data.points : [];
        app.classList.remove('hidden');
        updatePolyCount();
        setMessage('Polyzone saved to the form.', 'success');
        if (pendingCreateAfterPoly) {
            pendingCreateAfterPoly = false;
            form.requestSubmit();
        }
    }
});

document.getElementById('closeBtn').addEventListener('click', closePanel);
document.getElementById('listingCloseBtn').addEventListener('click', closePanel);

async function refreshPanel() {
    const result = await post('refresh');
    if (result.ok) { replaceHouses(result.houses); setMessage('Refreshed.', 'success'); }
    else setMessage(result.message || 'Refresh failed.', 'error');
}

document.getElementById('refreshBtn').addEventListener('click', refreshPanel);
document.getElementById('dashboardRefreshBtn').addEventListener('click', refreshPanel);

function newProperty() {
    pendingDeleteName = null;
    toggleDeleteConfirm(false);
    fillForm(null);
    if (currentLocation) applyCurrentLocation(currentLocation, true);
    setMessage('Creating a new property.', 'success');
    render();
    document.querySelector('.detailsPanel')?.scrollTo({ top: 0, behavior: 'smooth' });
}
document.getElementById('dashboardNewBtn').addEventListener('click', newProperty);
document.getElementById('search').addEventListener('input', render);
document.getElementById('statusFilter').addEventListener('change', render);

document.addEventListener('click', (event) => {
    const button = event.target.closest('button');
    if (!button) return;
    if (button.id === 'dashboardNewBtn') {
        event.preventDefault();
        event.stopImmediatePropagation();
        newProperty();
        return;
    }

    if (button.id === 'refreshBtn' || button.id === 'dashboardRefreshBtn') {
        event.preventDefault();
        event.stopImmediatePropagation();
        refreshPanel();
        return;
    }
}, true);

fields.propertyType.addEventListener('change', updateTypeGroups);
fields.image.addEventListener('input', () => renderImage(fields.image.value.trim()));
fields.garageEnabled.addEventListener('change', updateGarageVisibility);

document.getElementById('coordsBtn').addEventListener('click', async () => {
    const result = await post('beginSetEntrance');
    if (result.ok) {
        app.classList.add('hidden');
    } else {
        setMessage(result.message || 'Could not start entrance placement.', 'error');
    }
});

document.getElementById('garageBtn').addEventListener('click', async () => {
    if (!garageSupported()) {
        setMessage('Garage support is disabled in config.', 'error');
        return;
    }
    const result = await post('useCurrentGarage');
    if (result.ok && result.coords) {
        fields.garageEnabled.checked = true;
        updateGarageVisibility();
        fields.garageX.value = result.coords.x;
        fields.garageY.value = result.coords.y;
        fields.garageZ.value = result.coords.z;
        fields.garageW.value = result.coords.h;
        setMessage('Garage set to your current position.', 'success');
    } else {
        setMessage(result.message || 'Garage support is disabled in config.', 'error');
    }
});

document.getElementById('polyBtn').addEventListener('click', () => post('startPoly', { points: polyzone }));
document.getElementById('clearPolyBtn').addEventListener('click', () => { polyzone = []; updatePolyCount(); setMessage('Polyzone cleared.', 'success'); });
document.getElementById('scanDoorsBtn').addEventListener('click', () => {
    if (config.debug !== true) { setMessage('Door scanning is only available while Config.Debug is enabled.', 'error'); return; }
    if (fields.propertyType.value === 'shell') { setMessage('Door scan is for MLO/IPL properties.', 'error'); return; }
    if (polyzone.length < 3) { setMessage('Draw the property polyzone before scanning doors.', 'error'); return; }
    post('scanDoorLocks', {
        points: polyzone,
        name: fields.customName.value || fields.name.value || 'unnamed_property',
        label: fields.label.value || 'Unnamed Property',
        propertyType: fields.propertyType.value
    });
});
document.getElementById('clearDoorsBtn').addEventListener('click', () => { doorLocks = []; updateDoorCount(); setMessage('Door locks cleared.', 'success'); });
document.getElementById('waypointBtn').addEventListener('click', () => { const data = payload(); post('setWaypoint', { x: data.x, y: data.y }); });
document.getElementById('listingWaypointBtn').addEventListener('click', () => {
    if (!listingHouse) return;
    post('setWaypoint', { x: listingHouse.x, y: listingHouse.y });
});

function requestBuyProperty() {
    if (!listingHouse || listingHouse.owned || buyingProperty) return;
    pendingBuyName = listingHouse.name;
    setListingMessage('');
    toggleBuyConfirm(true);
}

async function confirmBuyProperty() {
    if (!listingHouse || listingHouse.owned || buyingProperty || pendingBuyName !== listingHouse.name) return;

    buyingProperty = true;
    document.getElementById('buyBtn').disabled = true;
    document.getElementById('buyYesBtn').disabled = true;
    document.getElementById('buyNoBtn').disabled = true;
    setListingMessage('Processing purchase...');

    try {
        const result = await post('buyHouse', { name: listingHouse.name });
        pendingBuyName = null;
        toggleBuyConfirm(false);
        if (result.ok) {
            updateListingHouseFromResult(result);
            setListingMessage('Property purchased.', 'success');
        } else {
            setListingMessage(result.message || 'Purchase failed.', 'error');
        }
    } catch (error) {
        pendingBuyName = null;
        toggleBuyConfirm(false);
        setListingMessage(error.message || 'Purchase failed.', 'error');
    } finally {
        buyingProperty = false;
        document.getElementById('buyBtn').disabled = false;
        document.getElementById('buyYesBtn').disabled = false;
        document.getElementById('buyNoBtn').disabled = false;
    }
}

function cancelBuyProperty() {
    pendingBuyName = null;
    toggleBuyConfirm(false);
    setListingMessage('');
}

document.getElementById('buyBtn').addEventListener('click', requestBuyProperty);
document.getElementById('previewBtn').addEventListener('click', async () => {
    if (!listingHouse) return;
    setListingMessage('Opening preview...');
    const result = await post('previewHouse', { name: listingHouse.name });
    if (!result.ok) setListingMessage(result.message || 'Could not preview house.', 'error');
});
document.getElementById('buyYesBtn').addEventListener('click', confirmBuyProperty);
document.getElementById('buyNoBtn').addEventListener('click', cancelBuyProperty);


document.getElementById('lockBtn').addEventListener('click', () => {
    if (!listingHouse) return;
    ownerPost('toggleLock', { name: listingHouse.name }, 'Lock state updated.');
});

function beginPointPlacement(pointType) {
    if (!listingHouse) return;
    app.classList.add('hidden');
    post('beginSetHousePoint', { name: listingHouse.name, pointType }).then((result) => {
        if (!result.ok) {
            app.classList.remove('hidden');
            setListingMessage(result.message || 'Could not start placement.', 'error');
        }
    }).catch((error) => {
        app.classList.remove('hidden');
        setListingMessage(error.message || 'Could not start placement.', 'error');
    });
}

document.getElementById('setExitBtn').addEventListener('click', () => beginPointPlacement('exit'));
document.getElementById('setStashBtn').addEventListener('click', () => beginPointPlacement('stash'));
document.getElementById('setWardrobeBtn').addEventListener('click', () => beginPointPlacement('wardrobe'));
document.getElementById('setLogoutBtn').addEventListener('click', () => beginPointPlacement('logout'));
document.getElementById('decorateBtn').addEventListener('click', async () => {
    if (!listingHouse) return;
    const result = await post('openFurniture', { name: listingHouse.name });
    if (result && result.ok) listingShell.classList.add('hiddenGroup');
    else setListingMessage(result && result.message ? result.message : 'Could not open decoration mode.', 'error');
});
document.getElementById('addDoorBtn').addEventListener('click', async () => {
    if (!listingHouse) return;
    setListingMessage('Opening door name prompt...');
    const result = await post('addHouseDoor', { name: listingHouse.name });
    if (result.ok && result.pending) {
        app.classList.add('hidden');
    } else if (!result.ok) {
        setListingMessage(result.message || 'Could not add door.', 'error');
    }
});
async function teleportDoor(door, setMessageFn) {
    if (!door || !door.coords) return;
    const result = await post("teleportDoor", { coords: door.coords, heading: door.heading || 0 });
    if (setMessageFn) setMessageFn(result.ok ? "Teleported to door." : (result.message || "Could not teleport."), result.ok ? "success" : "error");
}

function editDoorName(door, index) {
    const nextName = prompt("Door name", door.name || ("Door " + (index + 1)));
    return nextName && nextName.trim() ? nextName.trim().slice(0, 64) : null;
}

async function saveOwnerDoorList(doors, successText) {
    if (!listingHouse) return;
    const result = await post("saveHouseDoorList", { name: listingHouse.name, doors });
    if (result.ok) {
        updateListingHouseFromResult(result);
        setListingMessage(successText, "success");
    } else {
        setListingMessage(result.message || "Could not save doors.", "error");
    }
}

const adminDoorListEl = document.getElementById("adminDoorList");
if (adminDoorListEl) adminDoorListEl.addEventListener("click", async (event) => {
    const button = event.target.closest("button");
    const item = event.target.closest(".doorItem");
    if (!button || !item) return;

    const index = Number(item.dataset.index);
    const door = doorLocks[index];
    if (!door) return;

    if (button.dataset.action === "teleport") {
        await teleportDoor(door, setMessage);
    } else if (button.dataset.action === "edit") {
        const nextName = editDoorName(door, index);
        if (!nextName) return;
        doorLocks[index] = { ...door, name: nextName };
        updateDoorCount();
        setMessage("Door updated. Save Changes to keep it.", "success");
    } else if (button.dataset.action === "remove") {
        doorLocks.splice(index, 1);
        updateDoorCount();
        setMessage("Door removed from form. Save Changes to keep it.", "success");
    }
});

const ownerDoorListEl = document.getElementById("ownerDoorList");
if (ownerDoorListEl) ownerDoorListEl.addEventListener("click", async (event) => {
    const button = event.target.closest("button");
    const item = event.target.closest(".doorItem");
    if (!button || !item || !listingHouse) return;

    const index = Number(item.dataset.index);
    const doors = houseDoors(listingHouse);
    const door = doors[index];
    if (!door) return;

    if (button.dataset.action === "teleport") {
        await teleportDoor(door, setListingMessage);
    } else if (button.dataset.action === "edit") {
        const nextName = editDoorName(door, index);
        if (!nextName) return;
        doors[index] = { ...door, name: nextName };
        await saveOwnerDoorList(doors, "Door updated.");
    } else if (button.dataset.action === "remove") {
        doors.splice(index, 1);
        await saveOwnerDoorList(doors, "Door removed.");
    }
});

function requestSellHouse() {
    if (!listingHouse || sellingProperty) return;
    pendingSellName = listingHouse.name;
    setListingMessage('');
    toggleSellConfirm(true);
}

async function confirmSellHouse() {
    if (!listingHouse || sellingProperty || pendingSellName !== listingHouse.name) return;

    sellingProperty = true;
    document.getElementById('sellBtn').disabled = true;
    document.getElementById('sellYesBtn').disabled = true;
    document.getElementById('sellNoBtn').disabled = true;
    setListingMessage('Selling house...');

    try {
        const soldName = listingHouse.name;
        const result = await ownerPost('sellHouse', { name: soldName }, 'House sold.');
        pendingSellName = null;
        toggleSellConfirm(false);
        if (result && result.ok) {
            const nextHouse = houses.find((house) => house.name === soldName);
            if (nextHouse) showListingPanel(nextHouse);
        }
    } catch (error) {
        pendingSellName = null;
        toggleSellConfirm(false);
        setListingMessage(error.message || 'Sell failed.', 'error');
    } finally {
        sellingProperty = false;
        document.getElementById('sellBtn').disabled = false;
        document.getElementById('sellYesBtn').disabled = false;
        document.getElementById('sellNoBtn').disabled = false;
    }
}

function cancelSellHouse() {
    pendingSellName = null;
    toggleSellConfirm(false);
    setListingMessage('');
}

document.getElementById('sellBtn').addEventListener('click', requestSellHouse);
document.getElementById('sellYesBtn').addEventListener('click', confirmSellHouse);
document.getElementById('sellNoBtn').addEventListener('click', cancelSellHouse);


form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const wasEditing = Boolean(selected);
    const data = payload();
    if (!wasEditing && polyzone.length < 3) {
        pendingCreateAfterPoly = true;
        setMessage('Draw the property boundary, then press Enter to save it.', 'success');
        post('startPoly', { points: polyzone });
        return;
    }
    if (!wasEditing) {
        const generatedName = fields.customName.value.trim() || numberedPropertyName((currentLocation && currentLocation.nameBase) || fields.label.value);
        fields.customName.value = generatedName;
        data.name = generatedName;
    }

    const result = await post(wasEditing ? 'updateHouse' : 'createHouse', data);
    if (result.ok) {
        replaceHouses(result.houses);
        if (result.house) selectHouse(result.house);
        setMessage(wasEditing ? 'House updated.' : 'House created.', 'success');
    } else setMessage(result.message || 'Save failed.', 'error');
});

function requestDeleteSelectedProperty() {
    if (!selected || deletingProperty) return;
    pendingDeleteName = selected.name;
    setMessage('');
    toggleDeleteConfirm(true);
}

async function deleteSelectedProperty() {
    if (!selected || deletingProperty || pendingDeleteName !== selected.name) return;

    deletingProperty = true;
    document.getElementById('deleteBtn').disabled = true;
    document.getElementById('deleteTopBtn').disabled = true;
    document.getElementById('deleteYesBtn').disabled = true;
    document.getElementById('deleteNoBtn').disabled = true;
    setMessage('Deleting property...');

    try {
        const result = await post('deleteHouse', { name: selected.name });
        if (result.ok) {
            selected = null;
            pendingDeleteName = null;
            toggleDeleteConfirm(false);
            replaceHouses(result.houses);
            fillForm(null);
            setMessage('Property deleted from database.', 'success');
        } else {
            pendingDeleteName = null;
            toggleDeleteConfirm(false);
            setMessage(result.message || 'Delete failed.', 'error');
        }
    } catch (error) {
        pendingDeleteName = null;
        toggleDeleteConfirm(false);
        setMessage(error.message || 'Delete failed.', 'error');
    } finally {
        deletingProperty = false;
        document.getElementById('deleteBtn').disabled = false;
        document.getElementById('deleteTopBtn').disabled = false;
        document.getElementById('deleteYesBtn').disabled = false;
        document.getElementById('deleteNoBtn').disabled = false;
    }
}

function cancelDeleteSelectedProperty() {
    pendingDeleteName = null;
    toggleDeleteConfirm(false);
    setMessage('');
}

document.getElementById('deleteBtn').addEventListener('click', requestDeleteSelectedProperty);
document.getElementById('deleteTopBtn').addEventListener('click', requestDeleteSelectedProperty);
document.getElementById('deleteYesBtn').addEventListener('click', deleteSelectedProperty);
document.getElementById('deleteNoBtn').addEventListener('click', cancelDeleteSelectedProperty);

document.addEventListener('keyup', (event) => {
    if (event.key === 'Escape') {
        event.preventDefault();
        const furnitureShell = document.getElementById('furnitureShell');
        if (furnitureShell && !furnitureShell.classList.contains('hiddenGroup')) return;
        closePanel();
    }
});
