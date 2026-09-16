(() => {
    const shell = document.getElementById('furnitureShell');
    const rootApp = document.getElementById('app');
    const listing = document.getElementById('listingShell');
    const admin = document.getElementById('adminShell');
    const itemsPanel = document.getElementById('furnitureItems');
    const categoryBar = document.getElementById('furnitureCategoryBar');
    const confirmBox = document.getElementById('furnitureConfirm');
    const confirmText = document.getElementById('furnitureConfirmText');
    const loading = document.getElementById('furnitureLoading');
    const selectionTray = document.getElementById('furnitureSelectionTray');
    const selectionName = document.getElementById('furnitureSelectionName');
    const selectionPrice = document.getElementById('furnitureSelectionPrice');
    const placeButton = document.getElementById('furniturePlaceBtn');
    const objectsButton = document.getElementById('furnitureObjectsBtn');
    const ownedButton = document.getElementById('furnitureOwnedBtn');
    let catalog = {};
    let furniture = [];
    let selected = null;
    let activeHeader = null;
    let standaloneFurniture = false;
    let placementActiveUi = false;
    const placementNavigationKeys = new Set([
        'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
        'PageUp', 'PageDown'
    ]);

    function nuiPost(name, data = {}) {
        if (typeof GetParentResourceName !== 'function') return Promise.resolve({ ok: true });
        return fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
        }).then((response) => response.json());
    }

    function cash(value) {
        return `$${Number(value || 0).toLocaleString('en-US')}`;
    }

    function escapeHtml(value) {
        const element = document.createElement('span');
        element.textContent = String(value == null ? '' : value);
        return element.innerHTML;
    }

    function itemTile(item, owned = false) {
        const label = item.label || item.model || item.object || 'Furniture';
        const model = item.model || item.object || 'unknown_model';
        const initial = label.trim().charAt(0).toUpperCase() || 'F';
        const price = owned ? 'OWNED' : cash(item.price);
        return `<span class="qbDecorateItemIcon">${escapeHtml(initial)}</span><span class="qbDecorateItemMeta"><strong>${escapeHtml(label)}</strong><small>${escapeHtml(model)}</small></span><em>${price}</em>`;
    }

    function setActiveHeader(button) {
        [objectsButton, ownedButton].forEach((item) => item.classList.toggle('active', item === button));
        activeHeader = button;
    }

    function clearPanels() {
        itemsPanel.classList.add('hiddenGroup');
        categoryBar.innerHTML = '';
        selected = null;
        placementActiveUi = false;
        selectionTray.classList.add('hiddenGroup');
        document.querySelectorAll('.qbDecorateItem').forEach((item) => item.classList.remove('active'));
    }

    function showSelection(type, item) {
        selected = { type, item };
        selectionName.textContent = item.label || item.model || item.object || 'Furniture';
        selectionPrice.textContent = type === 'owned' ? 'OWNED' : cash(item.price);
        placeButton.textContent = type === 'owned' ? 'Save Position' : 'Place Furniture';
        selectionTray.classList.remove('hiddenGroup');
    }

    function hideSelection() {
        selected = null;
        selectionTray.classList.add('hiddenGroup');
    }

    function renderCategories() {
        categoryBar.innerHTML = '';
        Object.entries(catalog).forEach(([key, category]) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'qbDecorateCategoryButton';
            button.innerHTML = `<span>${escapeHtml(category.label || key)}</span><small class="qbDecorateCategoryCount">${(category.items || []).length}</small>`;
            button.addEventListener('click', () => {
                categoryBar.querySelectorAll('button').forEach((item) => item.classList.remove('active'));
                button.classList.add('active');
                renderCatalogItems(key);
            });
            categoryBar.appendChild(button);
        });
        const first = categoryBar.querySelector('button');
        if (first) first.click();
    }

    function renderCatalogItems(categoryKey) {
        const category = catalog[categoryKey] || { items: [] };
        itemsPanel.innerHTML = '';
        (category.items || []).forEach((item) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'qbDecorateItem';
            button.innerHTML = itemTile(item, false);
            button.addEventListener('click', async () => {
                itemsPanel.querySelectorAll('button').forEach((row) => row.classList.remove('active'));
                button.classList.add('active');
                showSelection('new', item);
                loading.classList.remove('hiddenGroup');
                const result = await nuiPost('furniturePreview', { model: item.object, price: item.price });
                loading.classList.add('hiddenGroup');
                if (!result || !result.ok) {
                    button.classList.remove('active');
                    hideSelection();
                    return;
                }
                await nuiPost('furnitureStartPlacement');
                placementActiveUi = true;
            });
            itemsPanel.appendChild(button);
        });
        if (!itemsPanel.children.length) itemsPanel.innerHTML = '<div class="emptyFurniture">No objects found in this category.</div>';
        itemsPanel.classList.remove('hiddenGroup');
    }

    function renderOwnedItems() {
        itemsPanel.innerHTML = '';
        furniture.forEach((item) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'qbDecorateItem';
            button.innerHTML = itemTile(item, true);
            button.addEventListener('click', async () => {
                itemsPanel.querySelectorAll('button').forEach((row) => row.classList.remove('active'));
                button.classList.add('active');
                showSelection('owned', item);
                const result = await nuiPost('furnitureEdit', { item });
                if (!result || !result.ok) {
                    button.classList.remove('active');
                    hideSelection();
                    return;
                }
                await nuiPost('furnitureStartPlacement');
                placementActiveUi = true;
                categoryBar.innerHTML = '';
                const remove = document.createElement('button');
                remove.type = 'button';
                remove.className = 'qbDecorateCategoryButton';
                remove.textContent = 'Remove';
                remove.addEventListener('click', async () => {
                    await nuiPost('furnitureDelete', { id: item.id });
                    hideSelection();
                    renderOwnedItems();
                });
                categoryBar.appendChild(remove);
            });
            itemsPanel.appendChild(button);
        });
        if (!furniture.length) itemsPanel.innerHTML = '<div class="emptyFurniture">No furniture has been placed in this property yet.</div>';
        itemsPanel.classList.remove('hiddenGroup');
    }

    async function commitSelection() {
        if (!selected || !confirmBox.classList.contains('hiddenGroup')) return;
        if (selected.type === 'new') {
            confirmText.textContent = `Are you sure you want to purchase this item for ${cash(selected.item.price)}?`;
            confirmBox.classList.remove('hiddenGroup');
            return;
        }
        placeButton.disabled = true;
        const result = await nuiPost('furnitureSave');
        placeButton.disabled = false;
        if (result && result.ok) hideSelection();
    }

    objectsButton.addEventListener('click', async () => {
        await nuiPost('furnitureResetSelection');
        hideSelection();
        setActiveHeader(objectsButton);
        renderCategories();
    });

    ownedButton.addEventListener('click', async () => {
        await nuiPost('furnitureResetSelection');
        hideSelection();
        setActiveHeader(ownedButton);
        categoryBar.innerHTML = '';
        renderOwnedItems();
    });

    document.getElementById('furnitureCloseBtn').addEventListener('click', () => nuiPost('furnitureClose'));
    placeButton.addEventListener('click', commitSelection);
    document.getElementById('furnitureCancelBtn').addEventListener('click', async () => {
        await nuiPost('furnitureCancel');
        hideSelection();
    });
    document.getElementById('furnitureBuyBtn').addEventListener('click', async () => {
        confirmBox.classList.add('hiddenGroup');
        const result = await nuiPost('furnitureBuy');
        if (result && result.ok) hideSelection();
    });
    document.getElementById('furnitureBuyCancelBtn').addEventListener('click', async () => {
        confirmBox.classList.add('hiddenGroup');
        await nuiPost('furnitureCancel');
        hideSelection();
    });

    document.addEventListener('keydown', (event) => {
        if (shell.classList.contains('hiddenGroup')) return;
        if (placementActiveUi && placementNavigationKeys.has(event.key)) {
            event.preventDefault();
            event.stopPropagation();
            return;
        }
        if (event.key === 'Enter') commitSelection();
    }, true);

    document.addEventListener('keyup', (event) => {
        if (!shell.classList.contains('hiddenGroup') && (event.key === 'Escape' || event.key === 'Esc' || event.key === 'Backspace')) {
            event.preventDefault();
            event.stopPropagation();
            nuiPost('furnitureClose');
        }
    });

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.action === 'openFurniture') {
            standaloneFurniture = rootApp.classList.contains('hidden');
            rootApp.classList.remove('hidden');
            admin.classList.add('hiddenGroup');
            listing.classList.add('hiddenGroup');
            catalog = data.catalog || {};
            furniture = data.furniture || [];
            selected = null;
            activeHeader = null;
            [objectsButton, ownedButton].forEach((button) => button.classList.remove('active'));
            clearPanels();
            confirmBox.classList.add('hiddenGroup');
            loading.classList.add('hiddenGroup');
            shell.classList.remove('hiddenGroup');
            shell.setAttribute('aria-hidden', 'false');
            setActiveHeader(objectsButton);
            renderCategories();
        } else if (data.action === 'furnitureRows') {
            furniture = data.furniture || [];
            if (activeHeader === ownedButton) renderOwnedItems();
        } else if (data.action === 'furnitureConfirm') {
            confirmText.textContent = `Are you sure you want to purchase this item for ${cash(data.price)}?`;
            confirmBox.classList.remove('hiddenGroup');
        } else if (data.action === 'furniturePlacementDone') {
            placementActiveUi = false;
            hideSelection();
        } else if (data.action === 'closeFurniture') {
            shell.classList.add('hiddenGroup');
            shell.setAttribute('aria-hidden', 'true');
            clearPanels();
            confirmBox.classList.add('hiddenGroup');
            if (standaloneFurniture) rootApp.classList.add('hidden');
            else listing.classList.remove('hiddenGroup');
            standaloneFurniture = false;
        }
    });
})();
