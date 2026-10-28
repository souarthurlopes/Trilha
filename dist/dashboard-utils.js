export function attendanceAlerts(students, attendance){
 return students.map(student=>{const recent=attendance.filter(a=>a.studentId===student.id&&a.classId===student.classId).sort((a,b)=>b.date.localeCompare(a.date)).slice(0,4);return {...student,absences:recent.filter(a=>a.status==='absent').length,recorded:recent.length}}).filter(s=>s.absences>=2).sort((a,b)=>b.absences-a.absences||a.name.localeCompare(b.name,'pt-BR'));
}
export function prioritizeNotices(notices){return [...notices].sort((a,b)=>Number(b.category==='important')-Number(a.category==='important')||String(b.date||'').localeCompare(String(a.date||'')))}
