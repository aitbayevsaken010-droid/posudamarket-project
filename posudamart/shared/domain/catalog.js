(function initPosudamartCatalogDomain() {
  if (window.PM_CATALOG) return;

  const { PM_ENUMS, PM_ACCESS } = window;

  function ensureNonEmpty(value, message) {
    if (!String(value || '').trim()) throw new Error(message);
  }

  function normalizeArticle(article) {
    return String(article || '').trim().toUpperCase().replace(/\s+/g, '-');
  }

  function normalizeImageUrl(url) {
    const raw = String(url || '').trim();
    if (!raw) return '';
    if (raw.startsWith('https://')) return raw;
    if (/^data:image\/(?:png|jpeg|jpg|webp|gif|bmp|svg\+xml);base64,[a-z0-9+/=\s]+$/i.test(raw)) {
      return raw.replace(/\s+/g, '');
    }
    return '';
  }

  function toMoney(value) {
    const num = Number(value);
    return Number.isFinite(num) ? num : 0;
  }

  function validateSupplierOffering(payload) {
    ensureNonEmpty(payload.name, 'Название товара обязательно.');
    ensureNonEmpty(payload.article, 'Артикул обязателен.');
    if (!payload.categoryId) throw new Error('Категория обязательна.');

    const unitsPerBox = Number(payload.unitsPerBox);
    if (!Number.isInteger(unitsPerBox) || unitsPerBox <= 0) {
      throw new Error('units_per_box должен быть целым числом > 0.');
    }

    const pricePerBox = toMoney(payload.pricePerBox);
    if (pricePerBox < 0) {
      throw new Error('price_per_box должен быть >= 0.');
    }

    return {
      name: String(payload.name).trim(),
      article: normalizeArticle(payload.article),
      categoryId: payload.categoryId,
      description: String(payload.description || '').trim() || null,
      unitsPerBox,
      pricePerBox,
      imageUrl: normalizeImageUrl(payload.imageUrl),
      isActive: payload.isActive !== false,
      variants: Array.isArray(payload.variants)
        ? payload.variants.map((v) => String(v || '').trim()).filter(Boolean)
        : [],
    };
  }

  async function assertSupplierAccess(sb) {
    const access = await PM_ACCESS.loadAccessContext(sb);
    if (!access || !PM_ACCESS.hasRouteAccess(access, [PM_ENUMS.ROLES.SUPPLIER])) {
      throw new Error('Только supplier может изменять supplier_products.');
    }
    if (!PM_ACCESS.canEnterBusinessSection(access)) {
      throw new Error('Роль supplier не активирована.');
    }
    return access;
  }

  async function loadCategories(sb) {
    const res = await sb.from('catalog_categories').select('id,name,is_active').eq('is_active', true).order('name');
    if (res.error) throw new Error(res.error.message);
    return res.data || [];
  }

  async function upsertSupplierProduct(sb, supplierUserId, rawPayload, existingId = null) {
    const payload = validateSupplierOffering(rawPayload);

    // canonical product by normalized article
    let productId = existingId ? rawPayload.productId : null;
    if (!productId) {
      const productRes = await sb
        .from('catalog_products')
        .select('id,article')
        .eq('article', payload.article)
        .maybeSingle();
      if (productRes.error) throw new Error(productRes.error.message);

      if (productRes.data?.id) {
        productId = productRes.data.id;
        const updateRes = await sb.from('catalog_products').update({
          name: payload.name,
          category_id: payload.categoryId,
          description: payload.description,
          is_active: payload.isActive,
          updated_at: new Date().toISOString(),
        }).eq('id', productId);
        if (updateRes.error) throw new Error(updateRes.error.message);
      } else {
        const insertProductRes = await sb.from('catalog_products').insert({
          article: payload.article,
          name: payload.name,
          category_id: payload.categoryId,
          description: payload.description,
          is_active: payload.isActive,
          created_by: supplierUserId,
        }).select('id').single();
        if (insertProductRes.error) throw new Error(insertProductRes.error.message);
        productId = insertProductRes.data.id;
      }
    }

    const imageUrl = payload.imageUrl;
    if (imageUrl) {
      await sb.from('catalog_product_images').delete().eq('product_id', productId).is('variant_id', null);
      const imageRes = await sb.from('catalog_product_images').insert({ product_id: productId, image_url: imageUrl, sort_order: 0 });
      if (imageRes.error) throw new Error(imageRes.error.message);
    }

    // replace variants for canonical product (simple stage-2 strategy)
    await sb.from('catalog_product_variants').delete().eq('product_id', productId);
    const variantIds = [];
    for (const variantName of payload.variants) {
      const vRes = await sb.from('catalog_product_variants').insert({ product_id: productId, variant_name: variantName }).select('id').single();
      if (vRes.error) throw new Error(vRes.error.message);
      variantIds.push(vRes.data.id);
    }

    const supplierPayload = {
      supplier_user_id: supplierUserId,
      product_id: productId,
      variant_id: null,
      supplier_article: payload.article,
      units_per_box: payload.unitsPerBox,
      price_per_box: payload.pricePerBox,
      is_active: payload.isActive,
      updated_at: new Date().toISOString(),
    };

    let result;
    if (existingId) {
      result = await sb.from('supplier_products').update(supplierPayload).eq('id', existingId).select('*').single();
    } else {
      result = await sb.from('supplier_products').insert(supplierPayload).select('*').single();
    }

    if (result.error) throw new Error(result.error.message);
    return result.data;
  }

  function mapSupplierRowsToWholesalerCatalog(rows) {
    return (rows || []).map((row) => ({
      supplierProductId: row.id,
      supplierUserId: row.supplier_user_id,
      supplierName: row.supplier_name || 'Supplier',
      categoryId: row.category_id,
      categoryName: row.category_name || 'Без категории',
      productId: row.product_id,
      article: row.article,
      name: row.product_name,
      description: row.description || '',
      imageUrl: row.image_url || '',
      unitsPerBox: Number(row.units_per_box || 0),
      pricePerBox: toMoney(row.price_per_box),
      derivedUnitPrice: toMoney(row.derived_unit_price || (row.units_per_box > 0 ? row.price_per_box / row.units_per_box : 0)),
      isActive: Boolean(row.supplier_product_active && row.product_active),
      variants: row.variants || [],
    }));
  }

  function mapWholesalerRowsToCustomerCatalog(rows) {
    return (rows || []).map((row) => ({
      inventoryItemId: row.id,
      wholesalerId: row.wholesaler_id,
      wholesalerName: row.wholesaler_name || 'Оптовик',
      categoryId: row.category_id,
      categoryName: row.category_name || 'Без категории',
      productId: row.product_id,
      article: row.article,
      name: row.product_name,
      imageUrl: row.image_url || '',
      unitSalePrice: toMoney(row.unit_sale_price),
      availableQty: Number(row.available_qty || 0),
    }));
  }

  window.PM_CATALOG = Object.freeze({
    normalizeArticle,
    normalizeImageUrl,
    validateSupplierOffering,
    assertSupplierAccess,
    loadCategories,
    upsertSupplierProduct,
    mapSupplierRowsToWholesalerCatalog,
    mapWholesalerRowsToCustomerCatalog,
  });
})();
