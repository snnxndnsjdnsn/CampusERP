import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatNumber } from '@/lib/format';

export type PropertyLand = { land_id: number; land_name: string; survey_number: string };
export type PropertyBuilding = { building_id: number; building_code: string; building_name: string; land_id: number | null; total_floors: number | null };
export type PropertyFloor = { floor_id: number; building_id: number; floor_number: number; floor_name: string | null };
export type PropertyRoom = { room_id: number; building_id: number; room_code: string };

function floorLabel(floor: PropertyFloor): string {
  return floor.floor_name ?? `Floor ${floor.floor_number}`;
}

/**
 * The property hierarchy of the institution structure module: every building,
 * the land parcel it stands on, its floors and the rooms on those floors.
 *
 * The rows are stitched here from four plain reads (land, building, floor,
 * room) because the panel below edits them one table at a time - this card is
 * where their connections are visible at a glance.
 */
export function PropertyHierarchy({
  lands,
  buildings,
  floors,
  rooms,
}: {
  lands: PropertyLand[];
  buildings: PropertyBuilding[];
  floors: PropertyFloor[];
  rooms: PropertyRoom[];
}) {
  const landById = new Map(lands.map((l) => [l.land_id, l]));

  return (
    <Card className="mb-6">
      <CardHeader>
        <CardTitle>Property hierarchy</CardTitle>
        <CardDescription>
          Land, buildings, floors and rooms, and how they hang together: a parcel carries the
          buildings, a building its floors, a floor its rooms.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {buildings.length === 0 ? (
          <EmptyState
            title="No buildings yet"
            description="Add a campus, then a land parcel and its buildings, through the Manage panel above."
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Building</TableHead>
                <TableHead>Land parcel</TableHead>
                <TableHead>Floors</TableHead>
                <TableHead className="text-right">Rooms</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {buildings.map((b) => {
                const buildingFloors = floors.filter((f) => f.building_id === b.building_id);
                const buildingRooms = rooms.filter((r) => r.building_id === b.building_id);
                const land = b.land_id !== null ? landById.get(b.land_id) : undefined;
                return (
                  <TableRow key={b.building_id}>
                    <TableCell>
                      <div className="font-medium">{b.building_name}</div>
                      <div className="text-xs text-muted-foreground">{b.building_code}</div>
                    </TableCell>
                    <TableCell>
                      {land ? (
                        <>
                          <div>{land.land_name}</div>
                          <div className="text-xs text-muted-foreground">Survey {land.survey_number}</div>
                        </>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </TableCell>
                    <TableCell>
                      {buildingFloors.length > 0 ? (
                        <div className="flex flex-wrap gap-1">
                          {buildingFloors.map((f) => (
                            <span
                              key={f.floor_id}
                              className="rounded bg-muted px-1.5 py-0.5 text-xs text-muted-foreground"
                            >
                              {floorLabel(f)}
                            </span>
                          ))}
                        </div>
                      ) : (
                        <span className="text-muted-foreground">
                          {b.total_floors !== null ? `${b.total_floors} planned` : '—'}
                        </span>
                      )}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{formatNumber(buildingRooms.length)}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
