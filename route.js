import { NextResponse } from 'next/server';

export async function GET(request) {
  try {
    const { searchParams } = new URL(request.url);
    const keyword = searchParams.get('keyword') || 'Profile Background';
    const requestedLimit = Number(searchParams.get('limit') || '10');

    const validLimits = [10, 28, 30, 50, 60, 100, 120];
    const limit = validLimits.includes(requestedLimit) ? requestedLimit : 10;

    const robloxUrl = `https://catalog.roblox.com/v1/search/items?category=Accessories&keyword=${encodeURIComponent(keyword)}&limit=${limit}`;

    const response = await fetch(robloxUrl, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Roblox API returned status ${response.status}: ${errorText}`);
    }

    const data = await response.json();

    return NextResponse.json(
      {
        success: true,
        data: Array.isArray(data?.data) ? data.data : data?.data || [],
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
