"""Page editor: turns a store owner's request in the builder chat into changes to
their home page sections ("add a categories section", "show 16 products",
"remove the story", "change the headline to ...").

The answer is checked again by the Rails app (PageLayout, PagePlan) before it is
saved, so this module only has to describe the change.
"""
import json
import logging
from typing import Any, Dict, List

from app.services.claude_llm import get_claude_llm

logger = logging.getLogger(__name__)

SECTION_TYPES = """
hero        Big welcome at the top. Words in texts.hero. Only once.
promises    Three short promises (delivery, returns...). Only once.
story       The shop's story with a photo. Words in texts.story. Only once.
steps       "How it works" in 3-4 steps. Words in texts.steps. Only once.
banner      Large banner with a photo and a button. Words in texts.banner. Only once.
products    Grid of the newest products. Settings: count (4-24), title, subtitle.
collection  Grid of products from ONE category. Settings: category (a permalink from
            the category list), count (4-24), title, subtitle.
categories  Picture tiles of the store's categories. Settings: count (2-12), title, subtitle.
faq         Questions and answers. Settings: title, items [{question, answer}] (max 8).
text        A block of text. Settings: title, text (paragraphs separated by a blank line).
reviews     Customer reviews. Settings: title, items [{quote, name}]. ONLY with reviews
            the owner wrote in their request, word for word. Never invent a review.
"""

PROMPT = """You edit the home page of an online store called "{store_name}".
About the store: {description}

The page is a list of sections, top to bottom. These section types exist:
{types}

The page now:
{sections}

Words of the existing sections (texts):
{texts}

Categories in this store (name -> permalink):
{categories}

The store has {product_count} products.

The owner asks:
\"\"\"{request}\"\"\"

Decide what kind of request this is:
- "layout": add, remove, move or change sections, their settings, or the words of
  hero/products/story/steps/banner. You can do it.
- "design": only colours, fonts, style, mood, spacing, photos' look. Not for you.
- "both": a layout part AND a design part. Do the layout part; put the design part,
  in the owner's words, in design_request.
- "unsupported": something the page cannot do (a video, a map, a pop-up, a new page,
  a section type not in the list, a category that does not exist...). Say so kindly
  in reply and suggest the closest thing that is possible.

Rules:
- Return the COMPLETE new list in "sections" (all sections, in order), not only the changes.
- Keep every section and setting the owner did not ask to change exactly as it is.
- Use only the section types above. hero, promises, story, steps, banner at most once.
- A "collection" must use a permalink from the category list. If the owner names a
  category that is not in the list, do not add it: say so in reply.
- If the store has fewer products than a count asked for, set the count anyway and
  mention in reply that more will show as products are added.
- Write any new words (FAQ answers, text, titles) for this store, in the language the
  owner writes in, short and concrete. FAQ answers must not promise things you do not
  know (prices, delivery times, policies): keep them general or ask the owner in reply
  to check them.
- Reviews: only quotes the owner wrote in the request. Never invent reviews or names.
- "texts" holds only fields you change, e.g. {{"hero": {{"title": "..."}}}}. Use the
  field names that already exist.
- reply: one or two friendly sentences to the owner saying exactly what you changed
  (or why not), in the owner's language. No markdown.

Answer with JSON only:
{{"kind": "layout|design|both|unsupported",
  "sections": [{{"type": "hero"}}, {{"type": "products", "count": 12, "title": "", "subtitle": ""}}],
  "texts": {{}},
  "design_request": "",
  "reply": ""}}
"""


def _compact(value: Any, limit: int) -> str:
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= limit else text[:limit] + "…"


def edit_page(request: str, store_name: str, description: str, sections: List[Dict[str, Any]],
              texts: Dict[str, Any], categories: List[Dict[str, str]], product_count: int) -> Dict[str, Any]:
    """Ask Claude for the change. Returns the parsed JSON answer (checked again in Rails)."""
    llm = get_claude_llm()
    category_lines = "\n".join(f"- {c.get('name', '')} -> {c.get('permalink', '')}" for c in categories[:40]) or "(none)"
    section_lines = "\n".join(f"{i + 1}. {json.dumps(s, ensure_ascii=False)}" for i, s in enumerate(sections)) or "(empty)"
    prompt = PROMPT.format(
        store_name=store_name or "the store",
        description=(description or "")[:600],
        types=SECTION_TYPES.strip(),
        sections=section_lines,
        texts=_compact(texts, 4000),
        categories=category_lines,
        product_count=int(product_count or 0),
        request=(request or "")[:500],
    )
    message = llm._create_message(max_tokens=4000,
                                  messages=[{"role": "user", "content": prompt}])
    text = "".join(getattr(block, "text", "") or "" for block in message.content)
    answer = llm._parse_json(text)
    if not isinstance(answer, dict):
        raise ValueError("The page editor did not return an object")
    logger.info(f"Page edit for '{store_name}': kind={answer.get('kind')} sections={len(answer.get('sections') or [])}")
    return answer
