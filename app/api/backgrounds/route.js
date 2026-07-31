import { NextResponse } from 'next/server';

const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  'Accept': 'application/json',
};

// Seed IDs: confirmed backgrounds used as a reliable starting point.
// The auto-discovery below will also find new ones added to the Roblox catalog.
const SEED_IDS = [
  121199209890990, // Prism Skies (Free)
  101873719747781, // Stargazer (200 R$)
  91937715974752,  // Soundwave (200 R$)
  116956243809295, // Graffiti Wall (200 R$)
  139579276427743, // Cloud Nine (200 R$)
  132272208178794, // Magic Music Bus (200 R$)
];

/**
 * Collects candidate item IDs from the Roblox catalog using multiple sort orders
 * for the Backgrounds subcategory, then merges them with the seed list.
 * The catalog filter is unreliable (returns mixed items), so every candidate
 * is validated against the economy API before being returned.
 */
async function collectCandidateIds() {
  const ids = new Set(SEED_IDS);

  // Query catalog with different sort types to maximize coverage of background items
  // sortType: 0=Relevance, 1=PriceLowToHigh, 2=PriceHighToLow, 3=RecentlyCreated
  const sortTypes = [0, 1, 2, 3];

  await Promise.all(
    sortTypes.map(async (sortType) => {
      try {
        const url = `https://catalog.roblox.com/v1/search/items/details?subcategory=Backgrounds&limit=30&sortType=${sortType}&salesTypeFilter=1`;
        const resp = await fetch(url, { headers: HEADERS });
        if (!resp.ok) return;
        const data = await resp.json();
        (data.data || []).forEach((item) => ids.add(item.id));
      } catch {}
    })
  );

  return [...ids];
}

/**
 * Validates a single asset ID against the Roblox economy API.
 * Returns the formatted item if it is a confirmed background (AssetTypeId=92),
 * or null if it is not a background or if the request fails.
 */
async function validateBackground(id) {
  try {
    const resp = await fetch(`https://economy.roblox.com/v2/assets/${id}/details`, {
      headers: HEADERS,
    });
    if (!resp.ok) return null;
    const d = await resp.json();
    if (d.AssetTypeId !== 92) return null;
    return {
      id,
      name: d.Name || 'Background',
      creatorName: d.Creator?.Name || 'Roblox',
      price: d.PriceInRobux || 0,
      description: d.Description || '',
      assetTypeId: 92,
      priceStatus: d.IsForSale ? 'ForSale' : 'NotForSale',
    };
  } catch {
    return null;
  }
}

export async function GET() {
  try {
    // Step 1: collect all candidate IDs (seed + catalog discovery)
    const candidateIds = await collectCandidateIds();
    console.log(`[API] Validating ${candidateIds.length} candidates...`);

    // Step 2: validate all candidates in parallel via economy API
    const results = await Promise.all(candidateIds.map(validateBackground));

    // Step 3: keep only confirmed backgrounds (AssetTypeId=92)
    const data = results.filter(Boolean);
    console.log(`[API] Returning ${data.length} confirmed backgrounds`);

    return NextResponse.json(
      { success: true, data },
      {
        status: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET',
          // Cache 24h on CDN; serve stale for 1h while revalidating in background
          'Cache-Control': 's-maxage=86400, stale-while-revalidate=3600',
        },
      }
    );
  } catch (error) {
    return NextResponse.json(
      { success: false, error: error.message || 'Internal Server Error' },
      {
        status: 500,
        headers: { 'Access-Control-Allow-Origin': '*' },
      }
    );
  }
}

