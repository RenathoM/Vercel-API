import { NextResponse } from 'next/server';

// Catalog endpoint that filters Roblox backgrounds by subcategory
export async function GET(request) {
  try {
    const { searchParams } = new URL(request.url);
    const subcategory = searchParams.get('subcategory') || 'Backgrounds';
    const requestedLimit = Number(searchParams.get('limit') || '28');

    // API only accepts these limits: 10, 28, 30
    const validLimits = [10, 28, 30];
    const limit = validLimits.includes(requestedLimit) ? requestedLimit : 28;

    // Use subcategory filter instead of keyword to get correct Background category items
    const robloxUrl = `https://catalog.roblox.com/v1/search/items/details?subcategory=${encodeURIComponent(subcategory)}&limit=${limit}&sortType=3&sortAggregation=5&salesTypeFilter=1`;

    console.log(`[API] Fetching backgrounds with subcategory="${subcategory}", limit=${limit}`);

    // Request Roblox Catalog API with User-Agent header (required)
    const response = await fetch(robloxUrl, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    });

    console.log(`[API] Response status: ${response.status}`);

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Roblox API returned status ${response.status}: ${errorText}`);
    }

    const data = await response.json();

    return NextResponse.json(
      {
        success: true,
        data: (data && data.data && Array.isArray(data.data)) ? data.data : [],
      },
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
