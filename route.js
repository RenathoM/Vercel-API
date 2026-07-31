import { NextResponse } from 'next/server';

export async function GET(request) {
  try {
    const { searchParams } = new URL(request.url);
    const keyword = searchParams.get('keyword') || 'Profile Background';
    const limit = searchParams.get('limit') || '10';

    const robloxUrl = `https://catalog.roblox.com/v1/search/items?category=Accessories&keyword=${encodeURIComponent(keyword)}&limit=${encodeURIComponent(limit)}`;

    const response = await fetch(robloxUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`Roblox API returned status ${response.status}`);
    }

    const data = await response.json();

    return NextResponse.json(data, {
      status: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET',
      },
    });
  } catch (error) {
    return NextResponse.json(
      { error: error.message || 'Internal Server Error' },
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
