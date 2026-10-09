import { describe, expect, it } from 'vitest';
import { previewImageCandidates, previewImageEvidence } from './pagePreview';

describe('associated page images', () => {
  it('distinguishes source-associated evidence from an unverified generic cover', () => {
    const url = 'https://shop.example/p/jacket';
    expect(previewImageEvidence({ url, title: 'Alpine Hybrid Sweater Jacket', html: '<meta property="og:image" content="/campaign.jpg">' }))
      .toEqual([{ url: 'https://shop.example/campaign.jpg', associated: false }]);
    expect(previewImageEvidence({ url, title: 'Alpine Hybrid Sweater Jacket', text: '![Alpine Hybrid Sweater Jacket](/jacket.jpg)' }))
      .toEqual([{ url: 'https://shop.example/jacket.jpg', associated: true }]);
  });
  it('rejects an invalid source and HTTP or IP image candidates', () => {
    expect(previewImageEvidence({ url: 'not a URL', html: '<link rel="canonical" href="https://shop.example/p/jacket">' })).toEqual([]);
    expect(previewImageCandidates({ url: 'https://shop.example/p/jacket', html: '<main><img src="http://images.example/jacket.jpg"><img src="https://127.0.0.1/jacket.jpg"></main>' })).toEqual([]);
  });
  it('preserves the complete Vince image URL with a parenthesized background color', () => {
    const image = 'https://cdn.media.amplience.net/i/vince/M19819120B_451LIB_001/Wool-Interlock-Johnny-Collar-Polo-Sweater-451LIB/?w=368&h=512&fmt=auto&qlt=default&bg=rgb(241%2C241%2C241)';
    expect(previewImageCandidates({ url: 'https://www.vince.com/product/example.html', title: 'Wool Interlock Johnny-Collar Polo Sweater',
      text: `![Wool Interlock Johnny-Collar Polo Sweater image number 0](${image})`,
    })).toEqual([image]);
  });
  it.each(['rgb(241%2C241%2C241)', 'rgb%28241%2C241%2C241%29'])('reaches usable Vince images after four undersized thumbnails with bg=%s', background => {
    const image = (n: number, width: number, height: number) => `https://cdn.media.amplience.net/i/vince/M19819120B_451LIB_00${n}/polo/?w=${width}&h=${height}&fmt=auto&bg=${background}`;
    const large = [image(1, 368, 512), image(2, 368, 512)];
    expect(previewImageCandidates({ url: 'https://www.vince.com/product/example.html', title: 'Wool Interlock Polo Sweater',
      text: [...[1, 2, 3, 4].map(n => image(n, 80, 110)), ...large].map(url => `![Wool Interlock Polo Sweater](${url})`).join('\n'),
    })).toEqual(large);
  });
  it.each([
    'https://cdn.media.amplience.net/i/shop/product?w=100&h=60',
    'https://cdn.media.amplience.net/i/shop/product?w=256&h=256',
    'https://cdn.media.amplience.net/i/shop/product?w=80&h=110&dpr=2',
    'https://cdn.media.amplience.net/i/shop/product?w=80&h=110&unknown=transform',
    'https://cdn.media.amplience.net/i/shop/product?w=80&w=368&h=512',
    'https://cdn.media.amplience.net/i/shop/product?w=80&h=110&h=512',
    'https://cdn.media.amplience.net/i/shop/product?w=80&h=110&maxW=368',
    'https://cdn.media.amplience.net/i/shop/product?w=80&h=invalid',
    'https://cdn.media.amplience.net/i/shop/product?w=0&h=50',
    'https://cdn.media.amplience.net/other/shop/product?w=80&h=110',
    'https://cdn.media.amplience.net.example.com/i/shop/product?w=80&h=110',
    'https://images.example/i/shop/product?w=80&h=110',
  ])('retains images when Amplience output dimensions are sufficient or uncertain: %s', image => {
    expect(previewImageCandidates({ url: 'https://shop.example/product', text: `![](${image})` })).toEqual([image]);
  });
  it.each(['w=99', 'h=59', 'w=99&h=200', 'w=200&h=59'])('filters known Amplience output dimensions below preview storage minimum: %s', size => {
    const image = `https://cdn.media.amplience.net/i/shop/product?${size}&fmt=auto&qlt=default&bg=white`;
    expect(previewImageCandidates({ url: 'https://shop.example/product', text: `![](${image})` })).toEqual([]);
  });
  it.each([
    ['![Front](https://images.example/photo_(front(blue)).jpg)', 'https://images.example/photo_(front(blue)).jpg'],
    ['![Front](<https://images.example/photo_(front).jpg> "Front view")', 'https://images.example/photo_(front).jpg'],
    [String.raw`![Front \] view](https://images.example/photo_\(front\).jpg 'Front \' view')`, 'https://images.example/photo_(front).jpg'],
    ['![Front](https://images.example/front.jpg (Front view))', 'https://images.example/front.jpg'],
  ])('reads bounded Markdown destination syntax: %s', (text, expected) => {
    expect(previewImageCandidates({ url: 'https://shop.example/product', text })).toEqual([expected]);
  });
  it.each([
    '![Front](https://images.example/photo_(front).jpg',
    '![Front](<https://images.example/front.jpg)',
    '![Front](https://images.example/front.jpg "unclosed)',
    '![Front](https://images.example/front.jpg trailing garbage)',
    String.raw`\![Front](https://images.example/front.jpg)`,
  ])('does not accept a truncated, malformed or escaped Markdown image: %s', text => {
    expect(previewImageCandidates({ url: 'https://shop.example/product', text })).toEqual([]);
  });
  it('bounds malformed Markdown and can still find a following well-formed image', () => {
    const image = 'https://images.example/good.jpg';
    const text = `![Unclosed${'['.repeat(10000)}\n![Too long](https://images.example/${'x'.repeat(20000)}.jpg)\n` +
      `![Unclosed destination](https://images.example/${'('.repeat(10000)}\n![](${image})`;
    expect(previewImageCandidates({ url: 'https://shop.example/product', text })).toEqual([image]);
  });
  it.each([
    '![The hero\ncontinued caption](https://images.example/hero.jpg)',
    '![Hero](https://images.example/hero.jpg\n "The hero")',
    '![Hero](https://images.example/hero.jpg "The\nhero")',
    '![incomplete then ![Hero](https://images.example/hero.jpg)',
  ])('recovers valid multiline or nested inline images: %s', text => {
    expect(previewImageCandidates({ url: 'https://shop.example/product', text })).toEqual(['https://images.example/hero.jpg']);
  });
  it('prefers the matching product over a generic social cover and unrelated graph products', () => {
    const result = previewImageCandidates({url:'https://shop.example/p/alpine-hybrid-sweater-jacket/mf26xs49.html?dwvar_mf26xs49_color=NAV',title:"Alpine Hybrid Sweater Jacket | Men's Sweaters",html:`
      <meta property="og:image" content="/campaign.jpg">
      <script type="application/ld+json">{"@graph":[
        {"@type":"Product","name":"Excursionist Crew","image":"/crew.jpg"},
        {"@type":"Product","name":"Alpine Hybrid Sweater Jacket","image":["/MF26XS49_RED.jpg","/MF26XS49_NAV.jpg"]}
      ]}</script>`});
    expect(result).toEqual(['https://shop.example/MF26XS49_NAV.jpg']);
  });
  it.each(['Logo', 'Icon', 'Pixel'])('keeps a source-bound %s product image while excluding navigation and icon assets', word => {
    const url = 'https://shop.example/p/crew-sweater';
    const name = `${word} Crew Sweater`;
    const result = previewImageEvidence({ url, title: name, html: `
      <meta property="og:image" content="/campaign.jpg">
      <script type="application/ld+json">${JSON.stringify({ '@type': 'Product', url, name,
        image: ['/nav/new-outerwear.jpg', '/assets/icon.png', 'https://cdn.example.com/product-123.jpg'] })}</script>` });
    expect(result).toEqual([{ url: 'https://cdn.example.com/product-123.jpg', associated: true }]);
  });
  it('does not retain a similarly named vest as a fallback for the saved jacket', () => {
    const url = 'https://shop.example/p/jacket';
    const result = previewImageCandidates({ url, title: 'Alpine Hybrid Sweater Jacket', html: `
      <script type="application/ld+json">${JSON.stringify({ '@graph': [
        { '@type': 'Product', url: 'https://shop.example/p/vest', sku: 'VEST', name: 'Alpine Hybrid Sweater Vest', image: '/vest.jpg' },
        { '@type': 'Product', url, sku: 'JACKET', name: 'Alpine Hybrid Sweater Jacket', image: '/jacket.jpg' },
      ] })}</script>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it('uses the canonical product identity when graph products have the same name', () => {
    const url = 'https://shop.example/p/jacket';
    const result = previewImageCandidates({ url: `${url}?utm_source=shared`, title: 'Alpine Hybrid Sweater Jacket', html: `
      <link rel="canonical" href="${url}">
      <script type="application/ld+json">${JSON.stringify({ '@graph': [
        { '@type': 'Product', url: 'https://shop.example/p/previous-jacket', sku: 'OLD-JACKET', name: 'Alpine Hybrid Sweater Jacket', image: '/previous-jacket.jpg' },
        { '@type': 'Product', url, sku: 'CURRENT-JACKET', name: 'Alpine Hybrid Sweater Jacket', image: '/current-jacket.jpg' },
      ] })}</script>` });
    expect(result).toEqual(['https://shop.example/current-jacket.jpg']);
  });
  it.each(['url', 'offers'] as const)('rejects a conflicting colour in Product %s even when its SKU and page-local id match', field => {
    const base = 'https://shop.example/p/jacket';
    const url = `${base}?dwvar_mf26xs49_color=NAV`;
    const redUrl = `${base}?dwvar_mf26xs49_color=RED`;
    const red = { '@type': 'Product', '@id': `${url}#red`, sku: 'MF26XS49', name: 'Alpine Hybrid Sweater Jacket', image: '/red-image.jpg',
      ...(field === 'url' ? { url: redUrl } : { offers: { '@type': 'Offer', url: redUrl } }) };
    const result = previewImageCandidates({ url, title: 'Alpine Hybrid Sweater Jacket', html: `
      <link rel="canonical" href="${base}">
      <script type="application/ld+json">${JSON.stringify({ '@graph': [red,
        { '@type': 'Product', url, sku: 'MF26XS49', name: 'Alpine Hybrid Sweater Jacket', image: '/navy-image.jpg' },
      ] })}</script>` });
    expect(result).toEqual(['https://shop.example/navy-image.jpg']);
  });
  it('does not let a local graph id override an explicitly different product URL', () => {
    const url = 'https://shop.example/p/jacket';
    const result = previewImageCandidates({ url, title: 'Alpine Hybrid Sweater Jacket', html: `
      <script type="application/ld+json">${JSON.stringify({ '@graph': [
        { '@type': 'Product', '@id': `${url}#suggested-product`, url: 'https://shop.example/p/vest', name: 'Alpine Hybrid Sweater Vest', image: '/vest.jpg' },
        { '@type': 'Product', '@id': `${url}#product`, url, name: 'Alpine Hybrid Sweater Jacket', image: '/jacket.jpg' },
      ] })}</script>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it('matches the source Product after removing known tracking parameters without a canonical tag', () => {
    const url = 'https://shop.example/p/jacket';
    const result = previewImageCandidates({ url: `${url}?utm_source=share&fbclid=click-id`, title: 'Alpine Hybrid Sweater Jacket', html: `
      <meta property="og:image" content="/campaign.jpg">
      <script type="application/ld+json">${JSON.stringify({ '@type': 'Product', url, name: 'Alpine Hybrid Sweater Jacket', image: '/jacket.jpg' })}</script>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it.each(['variant', 'sk', 'ref'])('preserves %s when comparing source and product identity', parameter => {
    const base = 'https://shop.example/p/jacket';
    const url = `${base}?${parameter}=saved-value`;
    const result = previewImageCandidates({ url: `${url}&utm_source=share`, title: 'Alpine Hybrid Sweater Jacket', html: `
      <script type="application/ld+json">${JSON.stringify({ '@graph': [
        { '@type': 'Product', '@id': `${url}&utm_source=share#other`, url: `${base}?${parameter}=other-value`, name: 'Alpine Hybrid Sweater Jacket', image: '/wrong.jpg' },
        { '@type': 'Product', url, name: 'Alpine Hybrid Sweater Jacket', image: '/jacket.jpg' },
      ] })}</script>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it('accepts the publisher canonical product path when the saved path is a variant identifier', () => {
    const canonical = 'https://shop.example/p/jacket?color=NAV';
    const result = previewImageCandidates({ url: 'https://shop.example/p/197889736936.html?dwvar_mf26xs49_color=NAV', title: 'Alpine Hybrid Sweater Jacket', html: `
      <link rel="canonical" href="${canonical}">
      <script type="application/ld+json">${JSON.stringify({ '@type': 'Product', url: canonical, sku: 'MF26XS49', name: 'Alpine Hybrid Sweater Jacket', image: '/navy-image.jpg' })}</script>` });
    expect(result).toEqual(['https://shop.example/navy-image.jpg']);
  });
  it('leaves ambiguous graph products unresolved when neither is bound to the saved page', () => {
    const result = previewImageCandidates({ url: 'https://shop.example/collection', html: `
      <script type="application/ld+json">${JSON.stringify({ '@graph': [
        { '@type': 'Product', url: 'https://shop.example/p/jacket', sku: 'JACKET', name: 'Alpine Hybrid Sweater Jacket', image: '/jacket.jpg' },
        { '@type': 'Product', url: 'https://shop.example/p/vest', sku: 'VEST', name: 'Alpine Hybrid Sweater Vest', image: '/vest.jpg' },
      ] })}</script>` });
    expect(result).toEqual([]);
  });
  it('uses the actual source heading to identify an image after the user renames the item', () => {
    const url = 'https://shop.example/p/jacket';
    const result = previewImageCandidates({ url, title: 'Gift for Alex', html: `
      <meta property="og:image" content="/campaign.jpg">
      <main><h1>Alpine Hybrid Sweater Jacket</h1></main>
      <script type="application/ld+json">${JSON.stringify({ '@type': 'Product', url, name: 'Alpine Hybrid Sweater Jacket', image: '/jacket.jpg' })}</script>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it('rejects navigation assets even when a provider calls them an OG image', () => {
    expect(previewImageCandidates({url:'https://shop.example/product',html:'<meta property="og:image" content="/nav/2026/new-outerwear.jpg">'})).toEqual([]);
  });
  it('ranks title-associated captured images before unrelated early promotional images and stops at Style With', () => {
    expect(previewImageCandidates({url:'https://shop.example/p/jacket',title:'Alpine Hybrid Sweater Jacket',text:`
![New outerwear](https://shop.example/promo.jpg)
![Alpine Hybrid Sweater Jacket in Navy](https://shop.example/jacket.jpg)
## Style With
![Alpine Hybrid Sweater Jacket styled with a belt](https://shop.example/belt.jpg)`})).toEqual(['https://shop.example/jacket.jpg']);
  });
  it('excludes an HTML Style With section even when related image text includes the saved title', () => {
    const result = previewImageCandidates({ url: 'https://shop.example/p/jacket', title: 'Alpine Hybrid Sweater Jacket', html: `
      <main><img src="/jacket.jpg" alt="Alpine Hybrid Sweater Jacket">
        <section><h2>Style With</h2><a href="/p/belt"><img src="/belt.jpg" alt="Alpine Hybrid Sweater Jacket styled with a belt"></a></section>
      </main>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it.each(['<span>Style With</span>', '<span>Style</span> <strong>With</strong>'])('recognizes related headings with nested markup: %s', heading => {
    const result = previewImageCandidates({ url: 'https://shop.example/p/jacket', title: 'Alpine Hybrid Sweater Jacket', html: `
      <main><img src="/jacket.jpg" alt="Alpine Hybrid Sweater Jacket">
        <section><h2>${heading}</h2><a href="/p/belt"><img src="/belt.jpg" alt="Alpine Hybrid Sweater Jacket styled with a belt"></a></section>
      </main>` });
    expect(result).toEqual(['https://shop.example/jacket.jpg']);
  });
  it('reads responsive and lazy main images without selecting navigation or footer assets', () => {
    expect(previewImageCandidates({url:'https://example.com/story',html:`<nav><img src="/nav.jpg"></nav>
<main><picture><source srcset="https://cdn.example.com/f_auto,q_auto/photo.jpg 1200w, /small.jpg 300w"><img src="data:image/gif;base64,x" alt="Mountain expedition"></picture>
<img data-src="/other.jpg" src="data:image/gif;base64,x" alt="Base camp"></main>`})).toEqual(['https://cdn.example.com/f_auto,q_auto/photo.jpg','https://example.com/small.jpg','https://example.com/other.jpg']);
  });
  it('retains alternate picture formats, responsive sizes and the img source for failed-download recovery', () => {
    const result = previewImageCandidates({ url: 'https://shop.example/p/jacket', title: 'Alpine Hybrid Sweater Jacket', html: `
      <main><picture>
        <source type="image/avif" srcset="/jacket.avif 1000w">
        <source type="image/webp" srcset="/jacket.webp 1000w">
        <img src="/jacket-default.jpg" srcset="/jacket-600.jpg 600w, /jacket-1200.jpg 1200w" alt="Alpine Hybrid Sweater Jacket">
      </picture></main>` });
    expect(result).toHaveLength(5);
    expect(result).toEqual(expect.arrayContaining([
      'https://shop.example/jacket.avif', 'https://shop.example/jacket.webp',
      'https://shop.example/jacket-1200.jpg', 'https://shop.example/jacket-600.jpg',
      'https://shop.example/jacket-default.jpg',
    ]));
    expect(result.indexOf('https://shop.example/jacket-1200.jpg')).toBeLessThan(result.indexOf('https://shop.example/jacket-600.jpg'));
  });
  it('rejects oversized raw OG image URLs before attempting responsive parsing', () => {
    const image = `https://cdn.example.com/${'a'.repeat(40000)}.jpg`;
    expect(previewImageCandidates({ url: 'https://shop.example/p/jacket', html: `<meta property="og:image" content="${image}">` })).toHaveLength(0);
  });
  it('recovers the product image already present in saved markdown, ignoring unrelated images', () => {
    const image = 'https://res.cloudinary.com/petermillar/image/upload/t_pdp_main/v1787663789/MF26XS49_NAV.jpg';
    const result = previewImageCandidates({ url: 'https://www.petermillar.com/p/alpine-hybrid-sweater-jacket/197889736936.html', title: 'Alpine Hybrid Sweater Jacket', text:
      `![Logo](https://example.com/logo.png)\n![Alpine Hybrid Sweater Jacket in Navy](${image})\n## You may also like\n![Other jacket](https://example.com/recommendation.jpg)\nProtected by reCAPTCHA` });
    expect(result).toEqual([image]);
  });
  it('resolves OG and JSON-LD article images, rejects credentials, trackers and favicons', () => {
    const result = previewImageCandidates({ url: 'https://example.com/story', html: `<meta content='/cover.jpg' property='og:image'>
      <script type="application/ld+json">{"@type":"Article","image":{"url":"https://cdn.example.com/article.jpg"}}</script>
      <article><img src='/favicon.ico'><img src='https://user:secret@example.com/photo.jpg'><img width='1' height='1' src='/pixel.gif'></article>` });
    expect(result).toEqual(['https://example.com/cover.jpg', 'https://cdn.example.com/article.jpg']);
  });
  it('takes images scoped to the public article/main DOM, not navigation or footer', () => {
    expect(previewImageCandidates({ url: 'https://example.com/story', html: `<nav><img src='/nav.jpg'></nav><main><img src='/hero.jpg' alt='The test apparatus'></main><footer><img src='/ad.jpg'></footer>` }))
      .toEqual(['https://example.com/hero.jpg']);
  });
  it('reaches the Medium article hero after undersized reader, publication and author crops', () => {
    const hero = 'https://miro.medium.com/v2/resize:fit:700/1*hero.jpeg';
    const text = `![Unknown user](https://miro.medium.com/v2/resize:fill:64:64/1*reader.png)
![Publication](https://miro.medium.com/v2/resize:fill:76:76/1*publication.png)
![Article author](https://miro.medium.com/v2/resize:fill:64:64/1*author.png)
![](${hero})`;
    expect(previewImageCandidates({ url: 'https://medium.com/@writer/example-article', text })).toEqual([hero]);
  });
  it('filters only known Medium fill crops below the storage dimension minimum', () => {
    const retained = [
      'https://miro.medium.com/v2/resize:fill:100:60/1*minimum.png',
      'https://miro.medium.com/v2/resize:fill:256:256/1*square.png',
      'https://miro.medium.com/v2/resize:fit:700/1*hero.jpeg',
      'https://example.com/v2/resize:fill:64:64/1*other.png',
      'https://miro.medium.com.example.com/v2/resize:fill:64:64/1*other.png',
    ];
    const rejected = [
      'https://miro.medium.com/v2/resize:fill:99:100/1*narrow.png',
      'https://miro.medium.com/v2/resize:fill:100:59/1*short.png',
    ];
    expect(previewImageCandidates({ url: 'https://medium.com/@writer/article',
      text: [...rejected, ...retained].map(url => `![](${url})`).join('\n'),
    })).toEqual(retained);
  });
});
