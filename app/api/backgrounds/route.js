import { NextResponse } from 'next/server';

// Curated list of confirmed Roblox Background asset IDs (assetTypeId=92).
// The catalog subcategory filter is unreliable — we use the economy API instead.
const KNOWN_BACKGROUND_IDS = [
  121199209890990, // Prism Skies (Free)
  101873719747781, // Stargazer (200 R$)
  91937715974752,  // Soundwave (200 R$)
  116956243809295, // Graffiti Wall (200 R$)
  139579276427743, // Cloud Nine (200 R$)
  132272208178794, // Magic Music Bus (200 R$)
];

// Catalog endpoint that returns confirmed Roblox background items
export async function GET(request) {
  try {
    // Fetch details for all known background IDs in parallel from the economy API
    const detailResults = await Promise.all(
      KNOWN_BACKGROUND_IDS.map(async (id) => {
        try {
          const res = await fetch(`https://economy.roblox.com/v2/assets/${id}/details`, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
          });
          if (!res.ok) return null;
          const d = await res.json();
          // Only return confirmed background assets
          if (d.AssetTypeId !== 92) return null;
          return {
            id,
            name: d.Name || 'Background',
            creatorName: d.Creator?.Name || 'Roblox',
            price: d.PriceInRobux || 0,
            description: d.Description || '',
            assetTypeId: d.AssetTypeId,
            priceStatus: d.IsForSale ? 'ForSale' : 'NotForSale',
          };
        } catch {
          return null;
        }
      })
    );

    const data = detailResults.filter(Boolean);
    console.log(`[API] Returning ${data.length} confirmed backgrounds`);

    return NextResponse.json(
      { success: true, data },
      {
        status: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET',
          'Cache-Control': 's-maxage=60, stale-while-revalidate=300',
        },
      }
    );
  } catch (error) {
    return NextResponse.json(
      {
        success: false,
        error: error.message || 'Internal Server Error',
      },
      {
        status: 500,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET',
        },
      }
    );
  }
}
