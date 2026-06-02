const PRODUCT = "https://kbmjk6ozhb.execute-api.ap-southeast-1.amazonaws.com/v1/products";
const CART = "https://kbmjk6ozhb.execute-api.ap-southeast-1.amazonaws.com/v2/cart";
const ORDER = "https://gf964wvxqb.execute-api.ap-southeast-1.amazonaws.com/orders";
const AUTH = ORDER.replace(/\/orders$/, "/auth");
const AUTH_REQUIRED_PAGES = ["index.html", "cart.html", "orders.html"];
const FALLBACK_IMAGE = "https://via.placeholder.com/300";
const SECONDARY_FALLBACK_IMAGE = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='300' height='200'%3E%3Crect width='300' height='200' fill='%23e5e7eb'/%3E%3Ctext x='50%25' y='50%25' dominant-baseline='middle' text-anchor='middle' fill='%234b5563' font-family='Arial' font-size='18'%3ENo Image%3C/text%3E%3C/svg%3E";
const LOCAL_CART_KEY = "keerthi_local_cart";

function parseApiList(payload) {
    try {
        if (!payload) return [];

        if (typeof payload.body === "string") {
            const parsed = JSON.parse(payload.body);
            return Array.isArray(parsed) ? parsed : [];
        }

        if (Array.isArray(payload.body)) {
            return payload.body;
        }

        if (Array.isArray(payload)) {
            return payload;
        }

        if (payload && Array.isArray(payload.items)) {
            return payload.items;
        }

        if (payload && Array.isArray(payload.value)) {
            return payload.value;
        }

        if (payload.body && payload.body.items && Array.isArray(payload.body.items)) {
            return payload.body.items;
        }

        return [];
    } catch (error) {
        console.log("parseApiList error:", error, payload);
        return [];
    }
}

function getSafeImageUrl(url) {
    if (!url || typeof url !== "string") return FALLBACK_IMAGE;

    const trimmed = url.trim();
    if (!trimmed) return FALLBACK_IMAGE;

    // Allow base64 data URLs for images.
    if (/^data:image\/[a-zA-Z+.-]+;base64,/.test(trimmed)) {
        return trimmed;
    }

    try {
        const parsed = new URL(trimmed);
        const isHttp = parsed.protocol === "http:" || parsed.protocol === "https:";
        if (!isHttp) return FALLBACK_IMAGE;

        // Reject search/result pages that are not direct image links.
        if (parsed.hostname.includes("bing.com") && parsed.pathname.includes("/images/search")) {
            return FALLBACK_IMAGE;
        }

        return parsed.href;
    } catch (error) {
        return FALLBACK_IMAGE;
    }
}

function getProductCardHtml(p) {
    const imageUrl = getSafeImageUrl(p.image);
    const safeName = p.name || "Product";
    const popularity = Number(p._popularity || p.popularity || 0);
    const popBadge = popularity > 0 ? `<div class="pop-badge">Popular: ${popularity}</div>` : "";
    return `
        <div class="card">
            <img src="${imageUrl}" onerror="if(this.src!=='${FALLBACK_IMAGE}'){this.src='${FALLBACK_IMAGE}';}else{this.onerror=null;this.src='${SECONDARY_FALLBACK_IMAGE}';}" alt="${safeName}">
            ${popBadge}
            <h3>${safeName}</h3>
            <p>₹ ${p.price}</p>
            <div style="display:flex;gap:8px;justify-content:center;margin-top:8px;">
                <button onclick="quickAdd('${p.product_id}')">Add to Cart</button>
                <button onclick="deleteProduct('${p.product_id}')" style="background:#ff4d4f;border:none;color:#fff;padding:8px 12px;border-radius:6px;cursor:pointer;">Delete</button>
            </div>
        </div>`;
}

/* DELETE PRODUCT */
async function deleteProduct(id) {
    const productId = String(id || "").trim();
    if (!productId) {
        alert('Invalid product id');
        return;
    }

    if (!confirm('Delete this product? This action cannot be undone.')) return;

    try {
        const response = await fetch(`${PRODUCT}?product_id=${encodeURIComponent(productId)}`, {
            method: 'DELETE'
        });

        const result = await response.json().catch(() => ({}));
        console.log('deleteProduct response:', result, 'status:', response.status);

        if (!response.ok || result.error) {
            alert('Failed to delete product');
            return;
        }

        alert('Product deleted');
        getProducts();
    } catch (error) {
        console.log('deleteProduct API error:', error);
        alert('Failed to delete product');
    }
}

function getLocalCart() {
    try {
        const raw = localStorage.getItem(LOCAL_CART_KEY);
        if (!raw) return [];
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
        console.log("getLocalCart error:", error);
        return [];
    }
}

function saveLocalCart(items) {
    localStorage.setItem(LOCAL_CART_KEY, JSON.stringify(items));
}

function addToLocalCart(productId) {
    const cart = getLocalCart();
    const existing = cart.find(i => String(i.product_id) === String(productId));
    if (existing) {
        existing.quantity = Number(existing.quantity || 1) + 1;
    } else {
        cart.push({ product_id: String(productId), quantity: 1 });
    }
    saveLocalCart(cart);
}

function normalizeCartItem(item) {
    const product_id = String(item.product_id || item.productId || item.id || "").trim();
    const quantity = Number(item.quantity || item.qty || item.count || 1);
    if (!product_id) return null;
    return { product_id, quantity: Number.isFinite(quantity) ? quantity : 1 };
}

function isOrderApiConfigured() {
    return typeof ORDER === "string" && ORDER.startsWith("http");
}

function currentPageName() {
    const path = window.location.pathname || "";
    const page = path.split("/").pop();
    return page || "index.html";
}

function isLoginPage() {
    return currentPageName() === "login.html";
}

function isLocalhostRun() {
    const host = window.location.hostname;
    return host === "localhost" || host === "127.0.0.1" || host === "::1";
}

async function getCurrentUser() {
    try {
        const response = await fetch(`${AUTH}/me`, {
            method: "GET",
            credentials: "include"
        });

        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.error || !result.user) return null;
        return result.user;
    } catch (error) {
        console.log("getCurrentUser error:", error);
        return null;
    }
}

async function logoutUser() {
    try {
        await fetch(`${AUTH}/logout`, {
            method: "POST",
            credentials: "include"
        });
    } catch (error) {
        console.log("logoutUser error:", error);
    }

    window.location.href = "login.html";
}

function enhanceNavForAuthenticatedUser(user) {
    const navLinks = document.querySelector(".nav-links");
    if (!navLinks) return;

    const loginLink = navLinks.querySelector(".login-link");
    if (loginLink) {
        loginLink.textContent = user?.full_name ? `Hi, ${user.full_name}` : "My Account";
        loginLink.href = "#";
        loginLink.onclick = (event) => {
            event.preventDefault();
            logoutUser();
        };
    }
}

async function enforceAuthentication() {
    const page = currentPageName();
    const user = await getCurrentUser();

    // Authentication is optional in local UI mode; do not force login redirects.
    if (user) {
        enhanceNavForAuthenticatedUser(user);
    }

    return true;
}

async function fetchNormalizedCartItems() {
    let cartList = [];

    try {
        const cartRes = await fetch(CART);
        const cartData = await cartRes.json();
        console.log("fetchNormalizedCartItems response:", cartData, "status:", cartRes.status);
        cartList = parseApiList(cartData)
            .map(normalizeCartItem)
            .filter(Boolean);
    } catch (error) {
        console.log("fetchNormalizedCartItems API error:", error);
    }

    const localCart = getLocalCart().map(normalizeCartItem).filter(Boolean);
    if (cartList.length === 0 && localCart.length > 0) {
        cartList = localCart;
    }

    return cartList;
}

async function fetchOrders() {
    try {
        const response = await fetch(ORDER);
        const data = await response.json();
        console.log("fetchOrders response:", data, "status:", response.status);

        return parseApiList(data);
    } catch (error) {
        console.log("fetchOrders API error:", error);
        return [];
    }
}

/* ADD PRODUCT */
async function addProduct(){
    const product_id = document.getElementById("pid_add").value;
    const name = document.getElementById("name").value;
    const price = document.getElementById("price").value;
    const image = document.getElementById("image").value;

    if(!product_id || !name || !price){
        alert("Enter Product ID, Name, and Price");
        return;
    }

    const payload = {
        product_id,
        name,
        price:Number(price),
        image: getSafeImageUrl(image)
    };

    console.log("addProduct request:", payload);

    const response = await fetch(PRODUCT,{
        method:"POST",
        headers:{"Content-Type":"application/json"},
        body:JSON.stringify(payload)
    });

    const result = await response.json().catch(() => ({}));
    console.log("addProduct response:", result);

    alert("Product Added");
    document.getElementById("pid_add").value = "";
    document.getElementById("name").value = "";
    document.getElementById("price").value = "";
    document.getElementById("image").value = "";
    getProducts();
}

/* GET PRODUCTS */
async function getProducts(){
    const productsEl = document.getElementById("products");
    if (!productsEl) return;

    let res = await fetch(PRODUCT);
    let data = await res.json();
    console.log("getProducts response:", data);

    let list = parseApiList(data);

    let html = "";

    list.forEach(p=>{
        html += getProductCardHtml(p);
    });

    productsEl.innerHTML = html;
}

/* RECOMMENDATIONS */
async function getRecommendations(count = 4) {
    const recEl = document.getElementById("recommendations");
    if (!recEl) return;
    try {
        const res = await fetch(PRODUCT);
        const data = await res.json().catch(() => ({}));
        let list = parseApiList(data);

        const cartList = await fetchNormalizedCartItems();
        const cartIds = new Set(cartList.map(i => String(i.product_id)));

        // Build popularity map from order history
        const orders = await fetchOrders();
        const popularityMap = {};
        orders.forEach(order => {
            const items = Array.isArray(order.cart_items) ? order.cart_items : [];
            items.forEach(it => {
                const pid = String(it.product_id || it.id || it.productId || "").trim();
                if (!pid) return;
                popularityMap[pid] = (popularityMap[pid] || 0) + (Number(it.quantity || it.qty || 1) || 1);
            });
        });

        // Exclude items already in cart
        let candidates = list.filter(p => !cartIds.has(String(p.product_id)));

        // Annotate popularity and sort by popularity desc, then price desc as tiebreaker
        candidates.forEach(p => {
            p._popularity = popularityMap[String(p.product_id)] || 0;
        });

        candidates.sort((a, b) => {
            const pa = Number(a._popularity || 0);
            const pb = Number(b._popularity || 0);
            if (pb !== pa) return pb - pa;
            return Number(b.price || 0) - Number(a.price || 0);
        });

        const selected = candidates.slice(0, count);
        recEl.innerHTML = selected.map(getProductCardHtml).join("");
    } catch (error) {
        console.log("getRecommendations error:", error);
        if (recEl) recEl.innerHTML = "";
    }
}

/* QUICK ADD */
function quickAdd(id){
    addCart(id);
}

/* ADD CART */
async function addCart(id){
    const productId = String(id || "").trim();

    if(!productId){
        alert("Unable to add to cart");
        return;
    }

    const payloadCandidates = [
        { product_id: productId },
        { id: productId },
        { productId: productId }
    ];

    let apiAdded = false;

    for (const payload of payloadCandidates) {
        try {
            console.log("addCart request:", payload);
            const response = await fetch(CART, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload)
            });
            const result = await response.json().catch(() => ({}));
            console.log("addCart response:", result, "status:", response.status);

            if (response.ok && !result.error) {
                apiAdded = true;
                break;
            }
        } catch (error) {
            console.log("addCart API error:", error);
        }
    }

    if (!apiAdded) {
        addToLocalCart(productId);
        console.log("addCart fallback: added to local cart", { product_id: productId });
    }

    alert("Added to cart");
}

/* GET CART */
async function getCart(){
    const cartEl = document.getElementById("cart");
    const cartEmptyEl = document.getElementById("cartEmpty");
    if (!cartEl || !cartEmptyEl) return;

    const cartList = await fetchNormalizedCartItems();

    let prodRes = await fetch(PRODUCT);
    let prodData = await prodRes.json();
    console.log("getCart products response:", prodData);
    let prodList = parseApiList(prodData);

    let html = "";

    if(cartList.length === 0){
        cartEmptyEl.style.display = "block";
        cartEl.innerHTML = "";
    } else {
        cartEmptyEl.style.display = "none";

        cartList.forEach(item=>{
            const itemProductId = String(item.product_id);
            let product = prodList.find(p=>String(p.product_id) === itemProductId);

            if(product){
                html += `
                <div class="card">
                    <img src="${getSafeImageUrl(product.image)}" onerror="if(this.src!=='${FALLBACK_IMAGE}'){this.src='${FALLBACK_IMAGE}';}else{this.onerror=null;this.src='${SECONDARY_FALLBACK_IMAGE}';}" alt="${product.name || 'Product'}">
                    <h3>${product.name}</h3>
                    <p>₹ ${product.price}</p>
                    <p><strong>Qty: ${item.quantity || 1}</strong></p>
                    <button class="delete-btn" onclick="deleteCart('${item.product_id}')">Remove</button>
                </div>`;
            }
        });

        cartEl.innerHTML = html;
    }
}

async function deleteCartQuietly(id){
    const productId = String(id || "").trim();
    if (!productId) return;

    for (const key of ["product_id", "id", "productId"]) {
        try {
            const response = await fetch(`${CART}?${key}=${encodeURIComponent(productId)}`, {
                method: "DELETE"
            });
            const result = await response.json().catch(() => ({}));
            console.log("deleteCartQuietly response:", result, "status:", response.status, "key:", key);
            if (response.ok && !result.error) {
                break;
            }
        } catch (error) {
            console.log("deleteCartQuietly API error:", error, "key:", key);
        }
    }
}

/* DELETE CART */
async function deleteCart(id){
    const productId = String(id || "").trim();
    if (!productId) return;

    let deleted = false;

    for (const key of ["product_id", "id", "productId"]) {
        try {
            const response = await fetch(`${CART}?${key}=${encodeURIComponent(productId)}`, {
                method: "DELETE"
            });
            const result = await response.json().catch(() => ({}));
            console.log("deleteCart response:", result, "status:", response.status, "key:", key);
            if (response.ok && !result.error) {
                deleted = true;
                break;
            }
        } catch (error) {
            console.log("deleteCart API error:", error, "key:", key);
        }
    }

    const updatedLocalCart = getLocalCart().filter(i => String(i.product_id) !== productId);
    saveLocalCart(updatedLocalCart);
    if (!deleted) {
        console.log("deleteCart fallback: removed from local cart", productId);
    }

    alert("Removed from cart");
    getCart();
}

/* PLACE ORDER */
async function placeOrder(){
    if (!isOrderApiConfigured()) {
        alert("Order service is not configured yet. Run terraform apply and refresh.");
        return;
    }

    const cartList = await fetchNormalizedCartItems();
    if (cartList.length === 0) {
        alert("Your cart is empty");
        return;
    }

    const prodRes = await fetch(PRODUCT);
    const prodData = await prodRes.json();
    const prodList = parseApiList(prodData);

    const cartItems = [];
    let totalAmount = 0;

    cartList.forEach(item => {
        const product = prodList.find(p => String(p.product_id) === String(item.product_id));
        if (!product) return;

        const quantity = Number(item.quantity || 1);
        const price = Number(product.price || 0);

        cartItems.push({
            product_id: String(product.product_id),
            name: product.name || "Product",
            price,
            quantity,
            image: getSafeImageUrl(product.image)
        });

        totalAmount += price * quantity;
    });

    if (cartItems.length === 0) {
        alert("No valid items found to place order");
        return;
    }

    const payload = {
        cart_items: cartItems,
        total_amount: totalAmount,
        currency: "INR"
    };

    console.log("placeOrder request:", payload);

    const response = await fetch(ORDER, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
    });

    const result = await response.json().catch(() => ({}));
    console.log("placeOrder response:", result, "status:", response.status);

    if (!response.ok || result.error) {
        alert("Order failed. Please try again.");
        return;
    }

    for (const item of cartItems) {
        await deleteCartQuietly(item.product_id);
    }

    saveLocalCart([]);
    await getCart();

    alert(`Order placed successfully. Order ID: ${result.order_id || "N/A"}`);
    window.location.href = "orders.html";
}

function getOrderCardHtml(order) {
    const items = Array.isArray(order.cart_items) ? order.cart_items : [];
    const createdAt = order.created_at || "";
    const orderId = order.order_id || "N/A";
    const status = order.status || "PLACED";
    const totalAmount = order.total_amount ?? 0;

    const formattedDate = createdAt
        ? new Date(createdAt).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" })
        : "N/A";

    const formattedTotal = Number(totalAmount || 0).toLocaleString("en-IN");

    const itemsHtml = items.map(item => `
        <div class="order-item-row">
            <span class="order-item-name">${item.name || "Item"}</span>
            <span class="order-item-qty">Qty: ${item.quantity || 1}</span>
            <span class="order-item-price">₹ ${Number(item.price || 0).toLocaleString("en-IN")}</span>
        </div>
    `).join("");

    return `
        <div class="card order-card">
            <div class="order-header">
                <h3>Order</h3>
                <span class="order-status">${status}</span>
            </div>
            <p class="order-id-text">${orderId}</p>
            <div class="order-meta">
                <p><strong>Date:</strong> ${formattedDate}</p>
                <p><strong>Total:</strong> ₹ ${formattedTotal}</p>
            </div>
            <div class="order-items">${itemsHtml}</div>
        </div>
    `;
}

async function getOrders() {
    const ordersEl = document.getElementById("orders");
    const ordersEmptyEl = document.getElementById("ordersEmpty");
    if (!ordersEl || !ordersEmptyEl) return;

    const orders = await fetchOrders();

    if (!orders.length) {
        ordersEmptyEl.style.display = "block";
        ordersEl.innerHTML = "";
        return;
    }

    ordersEmptyEl.style.display = "none";
    ordersEl.innerHTML = orders.map(getOrderCardHtml).join("");
}

/* SEARCH */
async function searchProduct(){
    const productsEl = document.getElementById("products");
    if (!productsEl) return;
    const input = document.querySelector('.search');
    const raw = input ? input.value : '';
    const keyword = String(raw || '').toLowerCase().trim();

    // If the search box is empty, show full product list
    if (!keyword) {
        await getProducts();
        return;
    }

    try {
        const res = await fetch(PRODUCT);
        const data = await res.json().catch(() => ({}));
        console.log("searchProduct response:", data);

        const list = parseApiList(data);

        const filtered = list.filter(p => {
            const name = (p && p.name) ? String(p.name).toLowerCase() : '';
            return name.includes(keyword);
        });

        const html = filtered.map(p => getProductCardHtml(p)).join('');
        productsEl.innerHTML = html;
    } catch (error) {
        console.log('searchProduct API error:', error);
        // Fallback: show existing product list
        await getProducts();
    }
}

function handleLogin(event) {
    event.preventDefault();

    const email = document.getElementById("loginEmail").value.trim();
    const password = document.getElementById("loginPassword").value.trim();
    const messageEl = document.getElementById("loginMessage");

    const validation = validateLoginCredentials(email, password);

    if (!validation.valid) {
        messageEl.textContent = validation.message;
        messageEl.style.display = "block";
        return false;
    }

    loginUser(email, password, messageEl);

    return false;
}

async function loginUser(email, password, messageEl) {
    messageEl.textContent = "Signing in...";
    messageEl.style.display = "block";

    try {
        const response = await fetch(`${AUTH}/login`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            credentials: "include",
            body: JSON.stringify({ email, password })
        });

        const result = await response.json().catch(() => ({}));

        if (!response.ok || result.error) {
            messageEl.textContent = result.error || "Login failed. Check your credentials.";
            return;
        }

        messageEl.textContent = `Welcome back, ${result.user?.full_name || email}. Redirecting...`;

        setTimeout(() => {
            window.location.href = "index.html";
        }, 800);
    } catch (error) {
        console.log("loginUser error:", error);
        messageEl.textContent = "Unable to reach the auth service right now.";
    }
}

function validateLoginCredentials(email, password) {
    if (!email || !password) {
        return {
            valid: false,
            message: "Please enter both email and password."
        };
    }

    return {
        valid: true,
        message: "Login successful. Redirecting to the store..."
    };
}

/* AUTO LOAD */
window.onload = async function() {
    const canContinue = await enforceAuthentication();
    if (!canContinue) return;

    if (document.getElementById("products")) {
        getProducts();
    }
    if (document.getElementById("cart")) {
        getCart();
    }
    if (document.getElementById("orders")) {
        getOrders();
    }
    if (document.getElementById("recommendations")) {
        getRecommendations();
    }
};