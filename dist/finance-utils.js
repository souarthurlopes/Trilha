export function financeToday(now=new Date()){
 const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now).map(p=>[p.type,p.value]));return `${p.year}-${p.month}-${p.day}`;
}
export const formatMoney=cents=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(cents/100);
export function parseChargeAmount(input){
 const raw=String(input).trim().replace(/^R\$\s*/, '');let integer,fraction;
 const br=raw.match(/^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$/);
 const decimal=raw.match(/^(\d+)(?:\.(\d{1,2}))?$/);
 if(br){integer=br[1].replaceAll('.','');fraction=br[2]||''}else if(decimal){integer=decimal[1];fraction=decimal[2]||''}else throw Error('Informe um valor válido, como 120,00.');
 const cents=Number(integer)*100+Number(fraction.padEnd(2,'0'));if(!Number.isSafeInteger(cents)||cents<1||cents>999999999)throw Error('O valor deve estar entre R$ 0,01 e R$ 9.999.999,99.');return cents;
}
export function chargeStatus(charge,asOf=financeToday()){
 if(charge.state==='paid')return 'paid';if(charge.state==='canceled')return 'canceled';return charge.due_date<asOf?'overdue':charge.due_date===asOf?'today':'open';
}
export function financeSummary(charges,asOf=financeToday()){
 const open=charges.filter(c=>c.state==='open'),overdue=open.filter(c=>c.due_date<asOf),dueToday=open.filter(c=>c.due_date===asOf),future=open.filter(c=>c.due_date>=asOf).sort((a,b)=>a.due_date.localeCompare(b.due_date));
 const total=items=>items.reduce((n,c)=>n+c.amount_cents,0);const active=charges.filter(c=>c.state!=='canceled');
 return {open,overdue,dueToday,next:future[0]||null,openCents:total(open),overdueCents:total(overdue),paidCents:total(charges.filter(c=>c.state==='paid')),activeCount:active.length,status:!active.length?'none':overdue.length?'late':dueToday.length?'today':'current'};
}
